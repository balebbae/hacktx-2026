import XCTest
import QuartzCore
@testable import Familiar

@MainActor
final class ConsentFlowTests: XCTestCase {
    var perception: FakePerception!
    var transcriber: FakeTranscriber!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var paths: MemoryPaths!
    var store: JSONPeopleStore!
    var contacts: RecordingContactsBridge!
    var recorder: AudioChunkClipRecorder!
    var states: [ConsentState] = []
    var collector: Task<Void, Never>?

    func makeFlow(name: NameGuess = NameGuess(name: "Marcus", confidence: 0.9, source: "regex"), config: ConsentFlowConfig? = nil) -> SpokenConsentFlow {
        perception = FakePerception(); perception.tracks = [FakePerception.track(7), FakePerception.track(8, faceHeightPx: 120)]
        transcriber = FakeTranscriber(lines: []); speaker = LogSpeaker(simulateDuration: false); gate = CueGate()
        paths = .temporary(); store = JSONPeopleStore(paths: paths, modelID: "fake"); contacts = RecordingContactsBridge()
        recorder = AudioChunkClipRecorder(seconds: 60)
        let now = CACurrentMediaTime()
        recorder.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000 * 20), sampleRate: 16_000, timestamp: now - 10))
        var cfg = config ?? ConsentFlowConfig()
        if config == nil { cfg.listenTimeout = 1.5; cfg.reaskTimeout = 1; cfg.nameTimeout = 0.5; cfg.gatherTimeout = 0.5; cfg.extraGatherTimeout = 0.5; cfg.confirmTimeout = 1 }
        let flow = SpokenConsentFlow(perception: perception, transcriber: transcriber, speaker: speaker, cueGate: gate, peopleStore: store, contacts: contacts, nameExtractor: FixedName(guess: name), yesNo: RulesYesNoClassifier(), clipRecorder: recorder, meeting: StaticMeetingContext(placeName: "HackTX"), paths: paths, userName: { "Priya" }, nameGuess: nil, config: cfg)
        states = []
        let stream = flow.subscribe()
        collector = Task { [weak self] in for await s in stream { self?.states.append(s) } }
        return flow
    }

    private func waitFor(_ pred: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let t0 = Date()
        while !pred(), Date().timeIntervalSince(t0) < timeout { try? await Task.sleep(nanoseconds: 20_000_000) }
    }
    private var isListening: Bool { states.contains { if case .listening = $0 { return true }; return false } }

    func testSpokenYesSavesPersonWavContactAndIdentity() async throws {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        XCTAssertTrue(gate.consentActive)
        XCTAssertEqual(perception.bursts.first?.track, 7, "largest unknown facing track")
        XCTAssertTrue(speaker.texts.contains(Phrasebook.consentQuestion(userName: "Priya", name: "Marcus")))
        transcriber.emit(.init(speaker: .other, text: "Yes, sure."))
        await run.value
        guard case let .done(p)? = states.last else { return XCTFail("expected done, got \(String(describing: states.last))") }
        XCTAssertEqual(p.name, "Marcus")
        XCTAssertEqual(p.embeddings.count, 3)
        XCTAssertEqual(p.consent.kind, .spoken); XCTAssertEqual(p.consent.replyTranscript, "Yes, sure.")
        XCTAssertEqual(p.met.placeName, "HackTX")
        let clip = try XCTUnwrap(p.consent.clipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
        let bytes = try Data(contentsOf: clip)
        XCTAssertEqual(String(decoding: bytes.prefix(4), as: UTF8.self), "RIFF"); XCTAssertGreaterThan(bytes.count, 44)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.resolve(thumbnailPath: p.thumbnailPath).path))
        XCTAssertEqual(store.all().map(\.id), [p.id])
        XCTAssertEqual(contacts.created.map(\.name), ["Marcus"]); XCTAssertNotNil(store.all().first?.contactIdentifier)
        XCTAssertEqual(perception.assigned.first?.name, "Marcus"); XCTAssertEqual(perception.assigned.first?.personID, p.id)
        XCTAssertEqual(speaker.texts.last, Phrasebook.saved(name: "Marcus"))
        XCTAssertFalse(gate.consentActive)
        XCTAssertFalse(speaker.texts.contains { $0.contains("Familiar") })
    }

    func testTapYesWithoutNameAsksThenFallsBack() async throws {
        let flow = makeFlow(name: NameGuess(name: nil, confidence: 0, source: "regex"))
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        XCTAssertTrue(speaker.texts.contains(Phrasebook.consentQuestion(userName: "Priya", name: nil)))
        flow.tapAnswer(yes: true)
        await run.value
        XCTAssertTrue(speaker.texts.contains(Phrasebook.whatShouldICallYou))
        guard case let .done(p)? = states.last else { return XCTFail("expected done") }
        XCTAssertEqual(p.name, "Someone I met"); XCTAssertEqual(p.consent.kind, .tap)
    }

    func testNoSavesNothing() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        transcriber.emit(.init(speaker: .other, text: "Nah, I'm good."))
        await run.value
        XCTAssertEqual(states.last, .declined)
        XCTAssertTrue(store.all().isEmpty); XCTAssertTrue(contacts.created.isEmpty); XCTAssertTrue(perception.assigned.isEmpty)
        XCTAssertEqual(speaker.texts.last, Phrasebook.nothingSaved)
        XCTAssertFalse(gate.consentActive)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.consentsDir.path))?.count ?? 0, 0)
    }

    func testUnclearReasksOnceThenTimeoutDeclines() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        transcriber.emit(.init(speaker: .other, text: "what do you mean"))
        await run.value
        XCTAssertTrue(speaker.texts.contains(Phrasebook.wasThatAYes))
        XCTAssertEqual(speaker.texts.filter { $0 == Phrasebook.wasThatAYes }.count, 1)
        XCTAssertEqual(states.last, .declined); XCTAssertTrue(store.all().isEmpty)
    }

    func testTargetLossCancels() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        perception.tracks = []
        await run.value
        guard case .cancelled? = states.last else { return XCTFail("expected cancelled, got \(String(describing: states.last))") }
        XCTAssertEqual(speaker.texts.last, Phrasebook.theyLeft); XCTAssertTrue(store.all().isEmpty); XCTAssertFalse(gate.consentActive)
    }

    func testUserSegmentsAreIgnoredWhileListening() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        transcriber.emit(.init(speaker: .user, text: "yes yes yes"))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(store.all().isEmpty)
        flow.cancel()
        await run.value
        guard case .cancelled? = states.last else { return XCTFail("expected cancelled") }
    }

    func testConfirmFirstWaitsForUserYes() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: true) }
        await waitFor { [self] in speaker.texts.contains(Phrasebook.wantToRemember) }
        XCTAssertEqual(states.first, .confirmingWithUser)
        transcriber.emit(.init(speaker: .user, text: "yes"))
        await waitFor { [self] in isListening }
        transcriber.emit(.init(speaker: .other, text: "sure"))
        await run.value
        guard case .done? = states.last else { return XCTFail("expected done, got \(String(describing: states.last))") }
    }
}
