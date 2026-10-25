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
        answerBus.publish(.tap(yes))
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

        if confirmFirst {
            acceptedSpeakers = [.user, .none]
            state = .confirmingWithUser
            notBefore = clock()
            await speaker.speak(Utterance(text: Phrasebook.wantToRemember, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .user, earcon: true))
            guard !Task.isCancelled else { return }
            let answer = await firstAnswer(timeout: config.confirmTimeout)
            switch answer {
            case .tap(true), .spoken(.yes, _, _): break
            default: finish(.idle); return
            }
        }

        // gathering
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
        var embeddings = await gather(track: target.trackID, timeout: config.gatherTimeout)
        if Task.isCancelled { return }
        if embeddings == nil { finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return }
        if embeddings!.count < config.minEmbeddings {
            await speaker.speak(Utterance(text: Phrasebook.lookTowardMe, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            embeddings = await gather(track: target.trackID, timeout: config.extraGatherTimeout)
            if Task.isCancelled { return }
            if embeddings == nil { finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return }
            if embeddings!.count < config.minEmbeddings { finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return }
        }
        let gathered = embeddings!

        // asking
        var name = await resolveNameGuess()
        if Task.isCancelled { return }
        cueGate.consentActive = true
        state = .asking(name: name)
        let question = Phrasebook.consentQuestion(userName: userName(), name: name)
        lastQuestion = question
        let clipStart = clock()
        notBefore = clipStart
        await speaker.speak(Utterance(text: question, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: true))
        if Task.isCancelled { return }

        // listening
        state = .listening
        var answer: Answer?
        switch await awaitAnswer(timeout: config.listenTimeout, track: target.trackID) {
        case let .answer(a): answer = a
        case .timeout: answer = nil
        case .lost: finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return
        }
        if Task.isCancelled { return }
        if case .spoken(.unclear, _, _) = answer {
            notBefore = clock()
            await speaker.speak(Utterance(text: Phrasebook.wasThatAYes, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            switch await awaitAnswer(timeout: config.reaskTimeout, track: target.trackID) {
            case let .answer(a): answer = a
            case .timeout: answer = nil
            case .lost: finish(.cancelled(reason: Phrasebook.theyLeft)); await speakTheyLeft(); return
            }
            if Task.isCancelled { return }
        }
        let kind: ConsentRecord.Kind
        var replyTranscript = ""
        var replyEnd = clock()
        switch answer {
        case let .spoken(.yes, transcript, end): kind = .spoken; replyTranscript = transcript; replyEnd = end
        case .tap(true): kind = .tap; replyTranscript = "(tapped YES)"
        default:
            lastReply = answerText(answer)
            finish(.declined)
            await speaker.speak(Utterance(text: Phrasebook.nothingSaved, priority: 0, category: "consent", personID: nil, dedupeKey: nil, audience: .otherPerson, earcon: false))
            return
        }
        lastReply = replyTranscript

        // saving
        state = .saving
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
        if (try? clipRecorder.writeClip(from: clipStart - config.clipLead, to: replyEnd + config.clipTail, url: clipURL!)) != true { clipURL = nil }
        let record = ConsentRecord(kind: kind, at: Date(), askedText: question, replyTranscript: replyTranscript, clipURL: clipURL)
        var person = Person(id: id, name: finalName, phone: nil, embeddings: gathered, thumbnailPath: thumbnailPath, consent: record, met: meeting.current(), contactIdentifier: nil)
        perception.assignIdentity(track: target.trackID, personID: id, name: finalName)
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
        pendingReplies.append(text)
        let verdict = await yesNo.classify(text)
        answerBus.publish(.spoken(verdict, transcript: text, end: seg.end))
    }

    private var pendingReplies: [String] = []

    /// First tap or spoken verdict after `notBefore`, or nil on timeout.
    private func firstAnswer(timeout: TimeInterval) async -> Answer? {
        let stream = answerBus.subscribe()
        return await withTimeout(timeout) {
            for await a in stream { return a }
            return nil
        } ?? nil
    }

    private enum Awaited { case answer(Answer), lost, timeout }

    /// First answer, unless the target track disappears for ~0.8 s first.
    private func awaitAnswer(timeout: TimeInterval, track: Int) async -> Awaited {
        let stream = answerBus.subscribe()
        let poll = config.pollInterval
        let perception = self.perception
        let missesNeeded = max(1, Int((0.8 / poll).rounded()))
        return await withTaskGroup(of: Awaited.self) { group in
            group.addTask { for await a in stream { return .answer(a) }; return .timeout }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return .timeout }
            group.addTask {
                var misses = 0
                while !Task.isCancelled {
                    misses = perception.currentTracks().contains { $0.trackID == track } ? 0 : misses + 1
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
