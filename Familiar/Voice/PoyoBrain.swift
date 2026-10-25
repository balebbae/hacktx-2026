import Foundation
import QuartzCore
import os

/// Poyo's answers. One multimodal call per question: the current view (faces blacked out), what the phone knows
/// (`WorldModel.contextLine`), the last 30 s of speech and the question → `{say, action}`. Built-in commands never
/// leave the phone; actions run through `CommandRouter`, so consent still belongs to the other person.
@MainActor
final class PoyoBrain: ObservableObject {
    @Published private(set) var lines: [AgentLine] = []
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
    private let userName: () -> String
    private let knownNames: () -> [String]
    private let log = Logger(subsystem: "familiar", category: "brain")

    var consentActive: () -> Bool = { false }
    var wakeWordCollecting: () -> Bool = { false }
    var followUpWindow: TimeInterval = 8
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    private var followUpUntil: TimeInterval = -.infinity
    private var lastOtherAt: TimeInterval = -.infinity
    private var current: Task<Void, Never>?

    init(vision: VisionLLM, scene: CloudScene, perception: Perception, transcriber: Transcriber, speaker: Speaker, cueGate: CueGate, router: CommandRouter,
         userName: @escaping () -> String, knownNames: @escaping () -> [String]) {
        self.vision = vision; self.scene = scene; self.perception = perception; self.transcriber = transcriber; self.speaker = speaker
        self.cueGate = cueGate; self.router = router; self.userName = userName; self.knownNames = knownNames
    }

    func start(speech: AsyncStream<TranscriptSegment>, unparsed: AsyncStream<String>?) -> [Task<Void, Never>] {
        var tasks = [Task { [weak self] in for await seg in speech { await self?.hear(seg) } }]
        if let unparsed { tasks.append(Task { [weak self] in for await phrase in unparsed { await self?.ask(phrase) } }) }
        return tasks
    }

    // MARK: Input

    /// Ongoing speech: the wearer's next sentence after an answer is a follow-up (no wake word needed); otherwise
    /// only request-like sentences, and only when nobody else spoke in the last 10 s, are offered as [overheard].
    func hear(_ seg: TranscriptSegment) async {
        guard seg.isFinal, !consentActive() else { return }
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let now = clock()
        if seg.speaker == .other { lastOtherAt = now; followUpUntil = -.infinity; return }
        guard WakeWord.find(in: text) == nil, !wakeWordCollecting() else { return }
        if now <= followUpUntil {
            await ask(text)
        } else if QuestionFilter.isRequestLike(text), now - lastOtherAt > 10 {
            await ask(text, addressed: false)
        }
    }

    /// A request addressed to Poyo ("Poyo, …" that the parser did not recognise, a follow-up, or a button).
    func ask(_ phrase: String, addressed: Bool = true) async {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !consentActive() else { return }
        // Built-in commands stay on the phone, except "what's around me", which is what the live view is for.
        if addressed, let c = CommandParser.parse(text), c != .describeSurroundings {
            lines.append(AgentLine(role: .user, text: text))
            lines.append(AgentLine(role: .tool, text: "command \(c)"))
            await router.handle(c)
            followUpUntil = clock() + followUpWindow
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
            if let start = await say(line)?.lowerBound { lastLatency = start - t0 }
            followUpUntil = clock() + followUpWindow
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
        let snapshot = scene.redactedSnapshot()
        let known = knownNames()
        let speech = transcriber.recentSegments(seconds: 30).filter(\.isFinal).suffix(8)
            .map { "\($0.speaker == .other ? "Other" : "Wearer"): \($0.text)" }.joined(separator: "\n")
        let prompt = """
        Wearer: \(userName()). People you may name: \(known.isEmpty ? "none" : known.joined(separator: ", ")).
        Now: \(WorldModel.contextLine(tracks: perception.currentTracks(), reading: scene.reading, now: t0))\(snapshot == nil ? " (no image right now)" : "")
        Recent speech:
        \(speech.isEmpty ? "(none)" : speech)
        \(addressed ? "[to you]" : "[overheard]") \(text)
        """
        let json: [String: Any]
        do {
            json = try await vision.complete(system: Self.systemPrompt, text: prompt, imageJPEG: snapshot?.jpeg, schemaName: "PoyoReply", schema: Self.schema,
                                             maxTokens: 700, cacheKey: "poyo-brain-v1", timeout: 10)
        } catch {
            log.error("brain failed: \(error.localizedDescription, privacy: .public)")
            lines.append(AgentLine(role: .app, text: "error: \(error.localizedDescription)"))
            if addressed, !Task.isCancelled { await say(Phrasebook.assistantUnavailable) }
            return
        }
        guard !Task.isCancelled, !consentActive() else { return }

        if addressed, let command = Self.command(action: json["action"] as? String, name: json["name"] as? String, mode: json["mode"] as? String) {
            lines.append(AgentLine(role: .tool, text: "\(command)"))
            await router.handle(command)          // speaks its own confirmation; remember starts the consent flow
            followUpUntil = clock() + followUpWindow
            return
        }
        guard let line = SpeechSanitizer.clean(json["say"] as? String) else {
            lines.append(AgentLine(role: .agent, text: "SKIP"))
            return
        }
        lines.append(AgentLine(role: .agent, text: line))
        let window = await say(line, priority: addressed ? 0 : 1)
        if let start = window?.lowerBound { lastLatency = start - t0 }
        followUpUntil = clock() + followUpWindow
    }

    @discardableResult
    private func say(_ text: String, priority: Int = 0) async -> ClosedRange<TimeInterval>? {
        let u = Utterance(text: text, priority: priority, category: "agent", personID: nil, dedupeKey: priority == 0 ? nil : "agent", audience: .user, earcon: false)
        guard cueGate.admit(u) else { return nil }
        return await speaker.speak(u)
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
                       "action": ["type": "string", "enum": ["none", "remember", "call", "text", "mute", "unmute", "mode", "cancel"]],
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
    Read signs, screens and labels when asked, but never name badges or text on a person.
    [to you] messages are addressed to you: always answer. [overheard] messages are the wearer talking to someone \
    else: set say to SKIP unless they clearly asked something you can answer from what you see.
    Set action only when the wearer clearly asks for it: remember (save the person in front of them; the app asks \
    that person for permission, so never say they are saved), call or text (with name), mute, unmute, mode (quiet, \
    normal or chatty), cancel. Otherwise action is none and say holds the answer.
    Never say your own name. If you cannot tell, say so briefly.
    """
}
