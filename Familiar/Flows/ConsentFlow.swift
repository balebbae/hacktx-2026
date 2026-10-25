import Foundation
import QuartzCore

/// The heart of the demo: ask the other person out loud, listen for their yes, and only then remember them.
/// Publishes `ConsentState` for the UI; `tapAnswer` and `cancel` work from any state.
@MainActor
final class SpokenConsentFlow: ConsentFlow {
    enum Answer: Equatable { case spoken(YesNo, transcript: String, end: TimeInterval); case tap(Bool) }

    private let perception: Perception
    private let transcriber: Transcriber
    private let speaker: Speaker
    private let cueGate: CueGate
    private let peopleStore: PeopleStore
    private let contacts: ContactsBridge
    private let nameExtractor: NameExtractor
    private let yesNo: YesNoClassifier
    private let clipRecorder: ConsentClipRecorder
    private let meeting: MeetingContextProvider
    private let paths: MemoryPaths
    private let userName: () -> String
    private let nameGuess: NameGuessCache?
    private let clock: () -> TimeInterval
    let config: ConsentFlowConfig

    private let stateBus = EventBus<ConsentState>()
    private let answerBus = EventBus<Answer>()
    private var running: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var acceptedSpeakers: Set<SpeakerGuess> = [.other, .none]
    private var notBefore: TimeInterval = 0

    private(set) var state: ConsentState = .idle { didSet { stateBus.publish(state) } }
    private(set) var lastQuestion: String?
    private(set) var lastReply: String?
    var isActive: Bool {
        switch state { case .idle, .done, .declined, .cancelled: return false; default: return true }
    }

    init(perception: Perception, transcriber: Transcriber, speaker: Speaker, cueGate: CueGate, peopleStore: PeopleStore, contacts: ContactsBridge, nameExtractor: NameExtractor, yesNo: YesNoClassifier, clipRecorder: ConsentClipRecorder, meeting: MeetingContextProvider, paths: MemoryPaths, userName: @escaping () -> String, nameGuess: NameGuessCache?, config: ConsentFlowConfig, clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.perception = perception; self.transcriber = transcriber; self.speaker = speaker; self.cueGate = cueGate
        self.peopleStore = peopleStore; self.contacts = contacts; self.nameExtractor = nameExtractor; self.yesNo = yesNo
        self.clipRecorder = clipRecorder; self.meeting = meeting; self.paths = paths; self.userName = userName
        self.nameGuess = nameGuess; self.config = config; self.clock = clock
    }

    // MARK: ConsentFlow

    func subscribe() -> AsyncStream<ConsentState> { stateBus.subscribe() }

    func begin(confirmFirst: Bool) async {
        guard running == nil else { return }
        let task = Task { [weak self] in guard let self else { return }; await self.run(confirmFirst: confirmFirst) }
        running = task
        await task.value
        running = nil
    }

    func tapAnswer(yes: Bool) {
        guard isActive else { return }
        // The card (and its YES) is up while the question is still being spoken, before anyone subscribes to
        // answers; keep the tap so the wait that follows picks it up instead of hanging.
        pendingTap = yes
        answerBus.publish(.tap(yes))
    }

    private var pendingTap: Bool?

    private func takePendingTap() -> Answer? {
        defer { pendingTap = nil }
        return pendingTap.map { .tap($0) }
    }

    func cancel() {
        guard let running else { return }
        running.cancel()
        self.running = nil
        finish(.cancelled(reason: "cancelled"))
    }

    // MARK: Flow

    private func run(confirmFirst: Bool) async {
        startListeningToTranscripts()
        defer { stopListeningToTranscripts(); cueGate.consentActive = false }
        if confirmFirst { await runSuggested() } else { await runAsked() }
    }

    /// "Remember them" (button, wake word, agent): the app asks the other person out loud.
    private func runAsked() async {
        acceptedSpeakers = [.other, .none]
        guard let target = pickTarget() else {
            await speaker.speak(Utterance(text: Phrasebook.noOneToRemember, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
            finish(.cancelled(reason: Phrasebook.noOneToRemember)); return
        }
        state = .gathering(track: target.trackID)
        perception.requestBurst(track: target.trackID, seconds: 2)
        let guessed = currentNameGuess()
        Task { [speaker, userName] in
            let u = userName()
            await speaker.prewarm([Phrasebook.consentQuestion(userName: u, name: guessed), Phrasebook.consentQuestion(userName: u, name: nil), Phrasebook.wasThatAYes, Phrasebook.whatShouldICallYou, Phrasebook.nothingSaved, Phrasebook.theyLeft] + (guessed.map { [Phrasebook.saved(name: $0)] } ?? []))
        }
        guard let gathered = await gatherOrGiveUp(track: target.trackID) else { return }

        // asking
        let name = await resolveNameGuess()
        if Task.isCancelled { return }
        cueGate.consentActive = true
        pendingTap = nil
        state = .asking(name: name)
        let question = Phrasebook.consentQuestion(userName: userName(), name: name)
        lastQuestion = question
        let clipStart = clock()
        notBefore = clipStart
        await speaker.speak(Utterance(text: question, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: true))
        if Task.isCancelled { return }
        // Only what is said after the question counts: anything heard while it played is the question itself.
        notBefore = clock()

        // listening
        state = .listening
        guard let (kind, reply, replyEnd) = await listenForConsent(timeout: config.listenTimeout, track: target.trackID) else { return }
        state = .saving
        await save(track: target.trackID, gathered: gathered, name: name, kind: kind, question: question, reply: reply, clip: (clipStart, replyEnd))
    }

    /// Familiar noticed a conversation with someone it does not know: it asks the wearer, the wearer asks the other
    /// person themselves, and only the other person's yes (or tap) saves anything.
    private func runSuggested() async {
        acceptedSpeakers = [.user, .none]
        pendingTap = nil
        state = .confirmingWithUser
        await speaker.speak(Utterance(text: Phrasebook.shouldIAdd, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .user, earcon: true))
        guard !Task.isCancelled else { return }
        notBefore = clock()
        switch await firstAnswer(timeout: config.confirmTimeout) {
        case .tap(true), .spoken(.yes, _, _): break
        default: finish(.idle); return
        }
        guard pickTarget() != nil else {
            await speaker.speak(Utterance(text: Phrasebook.noOneToRemember, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
            finish(.cancelled(reason: Phrasebook.noOneToRemember)); return
        }

        // The wearer asks in their own words; the app stays quiet and listens for the other person.
        acceptedSpeakers = [.other, .none]
        ignoreQuestions = true
        holdUnclear = true
        cueGate.consentActive = true
        pendingTap = nil
        let question = Phrasebook.wearerAsksCard(userName: userName())
        lastQuestion = question
        let listenStart = clock()
        notBefore = listenStart
        state = .listening
        guard let (kind, reply, replyEnd) = await listenForConsent(timeout: config.wearerAskTimeout, track: nil) else { return }
        let asked = transcriber.recentSegments(seconds: clock() - listenStart + 1).last { $0.speaker == .user && $0.start >= listenStart - 0.5 }?.text ?? question

        state = .saving
        var name = await resolveNameGuess()
        if Task.isCancelled { return }
        if name == nil { name = await askForName() ?? config.fallbackName }
        if Task.isCancelled { return }
        await speaker.speak(Utterance(text: Phrasebook.scanningFace, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
        guard !Task.isCancelled, let target = pickTarget() else { finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return }
        state = .gathering(track: target.trackID)
        perception.requestBurst(track: target.trackID, seconds: 2)
        guard let gathered = await gatherOrGiveUp(track: target.trackID) else { return }
        state = .saving
        await save(track: target.trackID, gathered: gathered, name: name, kind: kind, question: "Asked by \(userName()): \(asked)", reply: reply, clip: (listenStart, replyEnd))
    }

    /// Embeddings for the save, with one "look toward me" retry. nil = gave up (state and speech already handled).
    private func gatherOrGiveUp(track: Int) async -> [FaceEmbedding]? {
        var embeddings = await gather(track: track, timeout: config.gatherTimeout)
        if Task.isCancelled { return nil }
        if let e = embeddings, e.count < config.minEmbeddings {
            await speaker.speak(Utterance(text: Phrasebook.lookTowardMe, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            embeddings = await gather(track: track, timeout: config.extraGatherTimeout)
            if Task.isCancelled { return nil }
        }
        guard let e = embeddings, e.count >= config.minEmbeddings else { finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return nil }
        return e
    }

    /// The other person's answer, with one "was that a yes?" for an unclear reply. nil = no consent (state and speech
    /// already handled). `track` nil: any unknown person in view keeps the question open.
    private func listenForConsent(timeout: TimeInterval, track: Int?) async -> (ConsentRecord.Kind, String, TimeInterval)? {
        heardUnclear = false
        defer { holdUnclear = false; ignoreQuestions = false }
        var answer: Answer?
        switch await awaitAnswer(timeout: timeout, track: track) {
        case let .answer(a): answer = a
        case .timeout: answer = heardUnclear ? .spoken(.unclear, transcript: "", end: clock()) : nil
        case .lost: finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return nil
        }
        if Task.isCancelled { return nil }
        if case .spoken(.unclear, _, _) = answer {
            holdUnclear = false
            ignoreQuestions = false
            notBefore = clock()
            await speaker.speak(Utterance(text: Phrasebook.wasThatAYes, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            notBefore = clock()
            switch await awaitAnswer(timeout: config.reaskTimeout, track: track) {
            case let .answer(a): answer = a
            case .timeout: answer = nil
            case .lost: finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return nil
            }
            if Task.isCancelled { return nil }
        }
        switch answer {
        case let .spoken(.yes, transcript, end): lastReply = transcript; return (.spoken, transcript, end)
        case .tap(true): lastReply = "(tapped YES)"; return (.tap, "(tapped YES)", clock())
        default:
            lastReply = answerText(answer)
            finish(.declined)
            await speaker.speak(Utterance(text: Phrasebook.nothingSaved, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            return nil
        }
    }

    private func save(track: Int, gathered: [FaceEmbedding], name: String?, kind: ConsentRecord.Kind, question: String, reply: String, clip: (start: TimeInterval, end: TimeInterval)) async {
        var name = name
        if name == nil {
            name = await askForName()
            if Task.isCancelled { return }
        }
        let finalName = name ?? config.fallbackName
        let id = UUID()
        var thumbnailPath = ""
        if let jpeg = gathered.first(where: { $0.thumbnailJPEG != nil })?.thumbnailJPEG {
            if let json = peopleStore as? JSONPeopleStore { thumbnailPath = (try? json.writeThumbnail(jpeg, for: id)) ?? "" }
            else { try? paths.ensureDirectories(); try? jpeg.write(to: paths.thumbnailURL(for: id), options: .atomic); thumbnailPath = paths.relativeThumbnailPath(for: id) }
        }
        var clipURL: URL? = paths.consentClipURL(for: id)
        if (try? clipRecorder.writeClip(from: clip.start - config.clipLead, to: clip.end + config.clipTail, url: clipURL!)) != true { clipURL = nil }
        let record = ConsentRecord(kind: kind, at: Date(), askedText: question, replyTranscript: reply, clipURL: clipURL)
        var person = Person(id: id, name: finalName, phone: nil, embeddings: gathered, thumbnailPath: thumbnailPath, consent: record, met: meeting.current(), contactIdentifier: nil)
        perception.assignIdentity(track: track, personID: id, name: finalName)
        do { try peopleStore.add(person) } catch { finish(.cancelled(reason: "save failed: \(error.localizedDescription)")); return }
        if let identifier = try? await contacts.create(for: person) {
            person.contactIdentifier = identifier
            try? peopleStore.add(person)
        }
        cueGate.consentActive = false
        await speaker.speak(Utterance(text: Phrasebook.saved(name: finalName), priority: 0, category: "consent", personID: id, dedupeKey: nil, audience: .user, earcon: true))
        nameGuess?.reset()
        finish(.done(person))
    }

    private func speakTheyLeft() async {
        await speaker.speak(Utterance(text: Phrasebook.theyLeft, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
    }

    private func finish(_ terminal: ConsentState) {
        cueGate.consentActive = false
        state = terminal
    }

    private func answerText(_ a: Answer?) -> String {
        switch a {
        case let .spoken(_, t, _): return t
        case .tap(let yes): return yes ? "(tapped YES)" : "(tapped NO)"
        case nil: return "(no answer)"
        }
    }

    // MARK: Target & embeddings

    /// The unknown track that faces the user with the largest face; ties go to the one whose mouth moved most.
    func pickTarget() -> TrackSnapshot? {
        let unknown = perception.currentTracks().filter { !$0.identity.isKnown }
        let facing = unknown.filter(\.isFacingUser)
        let pool = facing.isEmpty ? unknown : facing
        return pool.max { a, b in
            if a.faceHeightPx != b.faceHeightPx { return a.faceHeightPx < b.faceHeightPx }
            return (a.mouthOpenness ?? 0) < (b.mouthOpenness ?? 0)
        }
    }

    /// Polls `bestEmbeddings` until enough good ones exist or the timeout passes. nil = the track disappeared.
    private func gather(track: Int, timeout: TimeInterval) async -> [FaceEmbedding]? {
        let deadline = clock() + timeout
        var best: [FaceEmbedding] = []
        repeat {
            guard perception.currentTracks().contains(where: { $0.trackID == track }) else { return nil }
            best = perception.bestEmbeddings(track: track, max: 8).filter { $0.quality >= config.minQuality }
            if best.count >= config.minEmbeddings { return Array(best.prefix(5)) }
            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        } while clock() < deadline && !Task.isCancelled
        return best
    }

    private func currentNameGuess() -> String? {
        guard let g = nameGuess?.guess, let name = g.name, g.confidence >= config.nameConfidenceThreshold else { return nil }
        if name.lowercased() == userName().lowercased() { return nil }
        return name
    }

    /// Cache first; otherwise run the extractor over the rolling transcript (regex is instant, LLMs capped at 3 s).
    private func resolveNameGuess() async -> String? {
        if let cached = currentNameGuess() { return cached }
        let segs = transcriber.recentSegments(seconds: 90)
        let g = await withTimeout(3) { [nameExtractor, userName] in await nameExtractor.otherPersonName(segments: segs, userName: userName()) }
        guard let g, let name = g.name, g.confidence >= config.nameConfidenceThreshold, name.lowercased() != userName().lowercased() else { return nil }
        return name
    }

    private func askForName() async -> String? {
        notBefore = clock()
        await speaker.speak(Utterance(text: Phrasebook.whatShouldICallYou, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
        let replies = await collectReplies(timeout: config.nameTimeout)
        for text in replies {
            if let n = RegexNameExtractor.nameFromDirectReply(text, userName: userName()) { return n }
        }
        if !replies.isEmpty {
            let segs = replies.map { TranscriptSegment(text: $0, start: clock(), end: clock(), isFinal: true, speaker: .other) }
            let g = await withTimeout(config.nameTimeout) { [nameExtractor, userName] in await nameExtractor.otherPersonName(segments: segs, userName: userName()) }
            if let name = g?.name, (g?.confidence ?? 0) >= 0.6 { return name }
        }
        return nil
    }

    // MARK: Answers

    private func startListeningToTranscripts() {
        transcriptTask?.cancel()
        transcriptTask = Task { [weak self] in
            guard let self else { return }
            for await seg in self.transcriber.subscribe() {
                guard !Task.isCancelled else { return }
                await self.consider(seg)
            }
        }
    }

    private func stopListeningToTranscripts() { transcriptTask?.cancel(); transcriptTask = nil }

    private func consider(_ seg: TranscriptSegment) async {
        guard seg.isFinal, acceptedSpeakers.contains(seg.speaker), seg.end >= notBefore - 0.3 else { return }
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // While the wearer asks in their own words, their question is not an answer (speaker attribution is a guess).
        if ignoreQuestions, Self.looksLikeQuestion(text) { return }
        pendingReplies.append(text)
        let verdict = await yesNo.classify(text)
        if verdict == .unclear, holdUnclear { heardUnclear = true; return }
        answerBus.publish(.spoken(verdict, transcript: text, end: seg.end))
    }

    private var ignoreQuestions = false
    private var holdUnclear = false
    private var heardUnclear = false

    /// "Do you want to be added to my contacts?", "Hey, is it okay if…": a question, not a reply.
    static func looksLikeQuestion(_ text: String) -> Bool {
        let s = CommandParser.normalize(text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") { return true }
        let starters = ["do you", "would you", "can i", "could i", "may i", "is it", "is that", "mind if", "are you", "how about", "would it"]
        let words = s.split(separator: " ")
        for i in 0..<min(3, words.count) {
            let rest = words[i...].joined(separator: " ")
            if starters.contains(where: { rest.hasPrefix($0 + " ") || rest == $0 }) { return true }
        }
        return false
    }

    private var pendingReplies: [String] = []

    /// First tap or spoken verdict after `notBefore`, or nil on timeout.
    private func firstAnswer(timeout: TimeInterval) async -> Answer? {
        if let tap = takePendingTap() { return tap }
        let stream = answerBus.subscribe()
        defer { pendingTap = nil }
        return await withTimeout(timeout) {
            for await a in stream { return a }
            return nil
        } ?? nil
    }

    private enum Awaited { case answer(Answer), lost, timeout }

    /// First answer, unless the target track (or, with `track` nil, every unknown person) disappears for ~0.8 s first.
    private func awaitAnswer(timeout: TimeInterval, track: Int?) async -> Awaited {
        if let tap = takePendingTap() { return .answer(tap) }
        let stream = answerBus.subscribe()
        defer { pendingTap = nil }
        let poll = config.pollInterval
        let perception = self.perception
        let missesNeeded = max(1, Int((0.8 / poll).rounded()))
        return await withTaskGroup(of: Awaited.self) { group in
            group.addTask { for await a in stream { return .answer(a) }; return .timeout }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return .timeout }
            group.addTask {
                var misses = 0
                while !Task.isCancelled {
                    let present = perception.currentTracks().contains { t in track.map { t.trackID == $0 } ?? !t.identity.isKnown }
                    misses = present ? 0 : misses + 1
                    if misses >= missesNeeded { return .lost }
                    try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
                }
                return .timeout
            }
            let first = await group.next() ?? .timeout
            group.cancelAll()
            return first
        }
    }

    /// Everything the other person said within the window (for "What should I call you?").
    private func collectReplies(timeout: TimeInterval) async -> [String] {
        pendingReplies.removeAll()
        let stream = answerBus.subscribe()
        _ = await withTimeout(timeout) { () -> Bool in
            for await a in stream { if case .spoken = a { return true } }
            return false
        }
        // give a trailing fragment a moment to land
        try? await Task.sleep(nanoseconds: 150_000_000)
        return pendingReplies
    }
}
