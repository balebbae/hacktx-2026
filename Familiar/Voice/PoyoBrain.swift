import Foundation
import QuartzCore
import os

/// Poyo's answers. One multimodal call per question: the current view (faces blacked out), what the phone knows
/// (`WorldModel.contextLine`), what was said lately (`DialogueMemory`, as chat turns), the last 30 s of speech and
/// the question → `{say, action}`. Built-in commands never leave the phone; actions run through `CommandRouter`,
/// so consent still belongs to the other person.
@MainActor
final class PoyoBrain: ObservableObject {
    @Published private(set) var lines: [AgentLine] = [] {
        didSet { if let l = lines.last, lines.count > oldValue.count { DiagnosticLog.write("poyo \(l.role.rawValue): \(l.text)") } }
    }
    /// Seconds from the request reaching the brain to its answer starting to play.
    @Published private(set) var lastLatency: TimeInterval?
    @Published private(set) var busy = false

    private let vision: VisionLLM
    private let scene: CloudScene
    private let perception: Perception
    private let transcriber: Transcriber
    private let speaker: Speaker
    private let cueGate: CueGate
    private let router: CommandRouter
    let dialogue: DialogueMemory
    private let userName: () -> String
    private let knownNames: () -> [String]
    private let log = Logger(subsystem: "familiar", category: "brain")

    var consentActive: () -> Bool = { false }
    /// Recent action captions ("Someone crossing, left to right, close."), so "what's going on?" has motion.
    var actions: () -> String? = { nil }
    var wakeWordCollecting: () -> Bool = { false }
    /// Someone in view is visibly talking to the wearer right now: a sentence in the follow-up window is theirs,
    /// not a question for Poyo. Set by `FlowRuntime` from perception.
    var someoneElseTalking: () -> Bool = { false }
    /// Re-transcribes the seconds where a name is said (on-device recognition turns "Jagadeep" into "JD").
    var scribe: ScribeTranscriber?
    var audio: AudioChunkClipRecorder?
    /// Renames the remembered person in view (or the one just saved); returns what to say. Set by `FlowRuntime`.
    var rename: (String) async -> String = { _ in Phrasebook.nobodyToUpdate }
    /// After a question Poyo asked ("Which door, the left one?"): the next sentence is the reply, whatever it sounds like.
    var followUpWindow: TimeInterval = 8
    /// After a plain answer: a follow-up that sounds like one ("which side is the door?", "and the window?").
    var plainFollowUpWindow: TimeInterval = 6
    var listenWindow: TimeInterval = 8
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// How many earlier turns the model sees.
    var historyTurns = 8
    /// Inner-lip gap ÷ face height above which a mouth in view counts as talking (a talking mouth swings 0 → 0.12).
    static let talkingMouth = 0.06

    private var followUpUntil: TimeInterval = -.infinity
    /// The open window is after a plain answer: the sentence must sound like a follow-up and nobody else may be talking.
    private var followUpNeedsRequest = false
    /// Poyo just asked "What's their name?": the next sentence is the new name.
    private var awaitingNameUntil: TimeInterval = -.infinity
    private var current: Task<Void, Never>?

    init(vision: VisionLLM, scene: CloudScene, perception: Perception, transcriber: Transcriber, speaker: Speaker, cueGate: CueGate, router: CommandRouter,
         dialogue: DialogueMemory = DialogueMemory(), userName: @escaping () -> String, knownNames: @escaping () -> [String]) {
        self.vision = vision; self.scene = scene; self.perception = perception; self.transcriber = transcriber; self.speaker = speaker
        self.cueGate = cueGate; self.router = router; self.dialogue = dialogue; self.userName = userName; self.knownNames = knownNames
    }

    func start(speech: AsyncStream<TranscriptSegment>, unparsed: AsyncStream<String>?) -> [Task<Void, Never>] {
        var tasks = [Task { [weak self] in for await seg in speech { await self?.hear(seg) } }]
        if let unparsed { tasks.append(Task { [weak self] in for await phrase in unparsed { await self?.ask(phrase) } }) }
        return tasks
    }

    // MARK: Input

    /// Ongoing speech. In a busy room any sentence may be a stranger's, so Poyo never takes one on its own: only
    /// "Poyo, …" (the wake word, handled elsewhere), the sentence after a volume-button press (`listenNext`), the
    /// reply to a question Poyo just asked, and the name it just asked for reach it.
    func hear(_ seg: TranscriptSegment) async {
        guard seg.isFinal, !consentActive() else { return }
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, WakeWord.find(in: text) == nil, !wakeWordCollecting() else { return }
        let now = clock()
        if now <= awaitingNameUntil {
            awaitingNameUntil = -.infinity
            lines.append(AgentLine(role: .user, text: text))
            dialogue.record(.wearer, text, at: now)
            let heard = await scribe?.retranscribe(audio, from: seg.start, to: seg.end) ?? text
            guard let name = Self.spokenName(in: heard) ?? Self.spokenName(in: text) else { await say(Phrasebook.didNotGetThat); return }
            await renameAndSay(name)
        } else if now <= followUpUntil {
            let needsRequest = followUpNeedsRequest
            followUpUntil = -.infinity                  // one sentence, then back to silence
            // After a plain answer only a sentence that sounds like a follow-up counts, and not while someone in view
            // is visibly talking to the wearer: in a packed room that sentence is theirs.
            if needsRequest, !Self.soundsLikeFollowUp(text) || someoneElseTalking() { return }
            await ask(text)
        }
    }

    /// Push-to-talk (volume button): the next sentence within `listenWindow` is for Poyo, no wake word needed.
    func listenNext() {
        followUpUntil = clock() + listenWindow
        followUpNeedsRequest = false
        lines.append(AgentLine(role: .app, text: "listening"))
    }

    /// After every addressed answer the wearer may go on without the name: any sentence when Poyo asked something,
    /// a shorter window for request-like follow-ups after a plain answer. The window only opens because Poyo was
    /// addressed, so it never joins a conversation on its own.
    private func noteAnswered(asked: Bool) {
        followUpUntil = clock() + (asked ? followUpWindow : plainFollowUpWindow)
        followUpNeedsRequest = !asked
    }

    private static let followUpOpener = try! NSRegularExpression(pattern: "^(?:(?:and|ok|okay|also|which|what about|how about) \\S|thanks|thank you)")

    /// "which side is the door", "and the window?", "what about the table", "ok where's the exit" — but not "yeah"
    /// or "nice to meet you".
    static func soundsLikeFollowUp(_ text: String) -> Bool {
        if QuestionFilter.isRequestLike(text) { return true }
        let s = CommandParser.normalize(text)
        return !s.isEmpty && followUpOpener.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// A request addressed to Poyo ("Poyo, …" that the parser did not recognise, a follow-up, or a button).
    func ask(_ phrase: String, addressed: Bool = true) async {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !consentActive() else { return }
        // "Change their contact to Anish": on the phone, before the command grammar ("call them Anish" is not a call).
        // The name is re-transcribed from the audio, which spells unusual names far better.
        if addressed, let name = Self.renameTarget(in: text) {
            lines.append(AgentLine(role: .user, text: text))
            dialogue.record(.wearer, text, at: clock())
            var better: String?
            if let seg = transcriber.recentSegments(seconds: 15).last(where: { $0.isFinal && WakeWord.find(in: $0.text) != nil }),
               let heard = await scribe?.retranscribe(audio, from: seg.start, to: seg.end) {
                better = Self.renameTarget(in: WakeWord.find(in: heard) ?? heard)
            }
            await renameAndSay(better ?? name)
            return
        }
        // "Can you update his name?" with no name yet: ask, and take the next sentence as the name.
        if addressed, Self.isRenameRequest(text) {
            lines.append(AgentLine(role: .user, text: text))
            lines.append(AgentLine(role: .agent, text: Phrasebook.whatName))
            dialogue.record(.wearer, text, at: clock())
            await say(Phrasebook.whatName)
            awaitingNameUntil = clock() + 10
            return
        }
        // Built-in commands stay on the phone, except "what's around me", which is what the live view is for.
        if addressed, let c = CommandParser.parse(text), c != .describeSurroundings {
            lines.append(AgentLine(role: .user, text: text))
            lines.append(AgentLine(role: .tool, text: "command \(c)"))
            dialogue.record(.wearer, text, at: clock())
            await router.handle(c)
            noteAnswered(asked: false)
            return
        }
        // "What's around me?" with a scene reading under 4 s old: answer at once from it (people from the phone,
        // then the model's own summary) instead of waiting ~2.5 s for a fresh call.
        if addressed, CommandParser.parse(text) == .describeSurroundings, let r = scene.reading, clock() - r.at < 4, let summary = SpeechSanitizer.clean(r.summary) {
            let tracks = perception.currentTracks()
            let line = (tracks.isEmpty ? "" : RollCall.phrase(tracks: tracks) + " ") + summary
            lines.append(AgentLine(role: .user, text: text))
            lines.append(AgentLine(role: .agent, text: line))
            let t0 = clock()
            dialogue.record(.wearer, text, at: t0)
            if let start = await say(line)?.lowerBound { lastLatency = start - t0 }
            noteAnswered(asked: false)
            return
        }
        current?.cancel()                       // the newest question wins
        let task = Task { await self.answer(text, addressed: addressed) }
        current = task
        await task.value
    }

    // MARK: Answer

    private func answer(_ text: String, addressed: Bool) async {
        lines.append(AgentLine(role: .user, text: addressed ? text : "(overheard) \(text)"))
        guard vision.isConfigured else {
            if addressed { await say(Phrasebook.assistantUnavailable) }
            return
        }
        let t0 = clock()
        busy = true
        defer { busy = false }
        // What was said before this question, as chat turns; then the question itself becomes a turn.
        let history = DialogueMemory.messages(dialogue.turns(now: t0, limit: historyTurns))
        if addressed { dialogue.record(.wearer, text, at: t0) }
        let snapshot = await scene.redactedSnapshot()
        guard !Task.isCancelled else { return }
        let known = knownNames()
        let speech = transcriber.recentSegments(seconds: 30).filter(\.isFinal).suffix(8)
            .map { "\($0.speaker == .other ? "Other" : "Wearer"): \($0.text)" }.joined(separator: "\n")
        let prompt = """
        Wearer: \(userName()). People you may name: \(known.isEmpty ? "none" : known.joined(separator: ", ")).
        Now: \(WorldModel.contextLine(tracks: perception.currentTracks(), reading: scene.reading, now: t0, actions: actions()))\(snapshot == nil ? " (no image right now)" : "")
        Recent speech:
        \(speech.isEmpty ? "(none)" : speech)
        \(addressed ? "[to you]" : "[overheard]") \(text)
        """
        let json: [String: Any]
        do {
            json = try await vision.complete(system: Self.systemPrompt, history: history, text: prompt, imageJPEG: snapshot?.jpeg, schemaName: "PoyoReply", schema: Self.schema,
                                             maxTokens: 700, cacheKey: "poyo-brain-v1", timeout: 10)
        } catch {
            log.error("brain failed: \(error.localizedDescription, privacy: .public)")
            lines.append(AgentLine(role: .app, text: "error: \(error.localizedDescription)"))
            if addressed, !Task.isCancelled { await say(Phrasebook.assistantUnavailable) }
            return
        }
        guard !Task.isCancelled, !consentActive() else { return }

        if addressed, json["action"] as? String == "rename", let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            await renameAndSay(name)
            return
        }
        if addressed, let command = Self.command(action: json["action"] as? String, name: json["name"] as? String, mode: json["mode"] as? String) {
            lines.append(AgentLine(role: .tool, text: "\(command)"))
            await router.handle(command)          // speaks its own confirmation; remember starts the consent flow
            noteAnswered(asked: false)
            return
        }
        guard let line = SpeechSanitizer.clean(json["say"] as? String) else {
            lines.append(AgentLine(role: .agent, text: "SKIP"))
            return
        }
        lines.append(AgentLine(role: .agent, text: line))
        let window = await say(line, priority: addressed ? 0 : 1)
        if let start = window?.lowerBound { lastLatency = start - t0 }
        if addressed { noteAnswered(asked: line.hasSuffix("?")) }
    }

    private func renameAndSay(_ name: String) async {
        let reply = await rename(name)
        lines.append(AgentLine(role: .tool, text: "rename → \(reply)"))
        await say(reply)
        noteAnswered(asked: false)
    }

    private static let renamePatterns: [NSRegularExpression] = [
        "^(?:please |can you |could you )?(?:update|change|rename|set|fix|correct|edit|make)\\b.*\\b(?:contact|name)\\b.*?\\b(?:to|as)(?: be)? ([a-z][a-z'-]*(?: [a-z][a-z'-]*)?)(?: please| instead.*| not .*)?$",
        "^(?:their|his|her|this person's|that person's|the person's) name is (?:actually )?([a-z][a-z'-]*(?: [a-z][a-z'-]*)?)(?: please| instead.*| not .*)?$",
        "^(?:save|call) (?:them|him|her) (?:as )?([a-z][a-z'-]*)(?: instead.*| not .*)$",
    ].map { try! NSRegularExpression(pattern: $0) }

    static func isRenameRequest(_ text: String) -> Bool {
        let s = CommandParser.normalize(text)
        return s.range(of: "\\b(update|change|rename|fix|correct|edit)\\b.*\\b(name|contact)\\b", options: .regularExpression) != nil
            || s.range(of: "\\bwrong name\\b", options: .regularExpression) != nil
    }

    /// The name in an answer to "What's their name?": "His name is Jagadeep." / "It's Jagadeep" / "Jagadeep".
    static func spokenName(in text: String) -> String? {
        var s = CommandParser.normalize(text)
        s = s.replacingOccurrences(of: "^(?:(?:um|uh|so|oh|okay|ok) )*(?:(?:his|her|their|the|my) name is|it'?s|it is|that'?s|call (?:him|her|them)|they'?re|he'?s|she'?s|i'?m)\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b(please|actually|now|instead)\\b", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let words = s.split(separator: " ").prefix(2)
        guard let first = words.first, first.count >= 2, !["no", "yes", "the", "a", "um", "uh", "him", "her", "them"].contains(String(first)) else { return nil }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// "update their contact to be Anish instead of someone I know" → "Anish".
    static func renameTarget(in text: String) -> String? {
        let s = CommandParser.normalize(text)
        for re in renamePatterns {
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) else { continue }
            let name = String(s[r]).replacingOccurrences(of: "\\b(please|now)\\b", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !["them", "him", "her", "it", "someone", "quiet", "normal", "chatty"].contains(name) else { continue }
            return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return nil
    }

    @discardableResult
    private func say(_ text: String, priority: Int = 0) async -> ClosedRange<TimeInterval>? {
        let u = Utterance(text: text, priority: priority, category: "agent", personID: nil, dedupeKey: priority == 0 ? nil : "agent", audience: .user, earcon: false)
        guard cueGate.admit(u) else { return nil }
        let window = await speaker.speak(u)
        if window != nil { dialogue.record(.poyo, text, at: clock()) }   // the speaker hook records it too; same turn
        return window
    }

    static func command(action: String?, name: String?, mode: String?) -> Command? {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "remember": return .rememberThem
        case "call": return name.flatMap { $0.isEmpty ? nil : .call($0) }
        case "text": return name.flatMap { $0.isEmpty ? nil : .text($0) }
        case "mute": return .mute
        case "unmute": return .unmute
        case "mode": return ChatterMode(agentWord: mode ?? "").map { .setMode($0) }
        case "cancel": return .cancel
        default: return nil
        }
    }

    static let schema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": ["say": ["type": "string"],
                       "action": ["type": "string", "enum": ["none", "remember", "rename", "call", "text", "mute", "unmute", "mode", "cancel"]],
                       "name": ["type": ["string", "null"]], "mode": ["type": ["string", "null"]]],
        "required": ["say", "action", "name", "mode"],
    ]

    static let systemPrompt = """
    You are Poyo, the voice of camera glasses worn by a blind person. Your reply is spoken aloud. \
    Answer in one short sentence, at most 15 words, plain spoken English, no lists, no markdown.
    The image, when present, is the wearer's view right now. Its left edge is 11 o'clock, its centre 12 o'clock and \
    its right edge 1 o'clock. Give directions as clock positions and distances in meters or steps.
    Every face in the image is blacked out on purpose. Never mention that. Never describe anyone's looks, clothes, \
    body, age, gender or mood.
    The "Now:" line comes from the phone's own sensors: trust it for who is here and where. Only the people listed \
    under "People you may name" may be named, and only where "Now" places them; anyone else is "someone".
    Earlier turns are what you and the wearer said in the last few minutes; your own turns include the automatic \
    announcements the app made in your voice (who appeared or left, obstacles, alerts). Use them to resolve "he", \
    "that door", "which side"; do not repeat them unless asked.
    Read signs, screens and labels when asked, but never name badges or text on a person.
    [to you] messages are addressed to you: always answer. [overheard] messages are the wearer talking to someone \
    else: set say to SKIP unless they clearly asked something you can answer from what you see.
    Set action only when the wearer clearly asks for it: remember (save the person in front of them; the app asks \
    that person for permission, so never say they are saved), rename (change the saved name of the person they are \
    looking at; name holds the new name), call or text (with name), mute, unmute, mode (quiet, normal or chatty), cancel. Otherwise action is none and say holds the answer.
    Never say your own name. If you cannot tell, say so briefly.
    """
}
