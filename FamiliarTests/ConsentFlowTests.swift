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
    var backdate: TimeInterval = 0

    func makeFlow(name: NameGuess = NameGuess(name: "Marcus", confidence: 0.9, source: "regex"), config: ConsentFlowConfig? = nil) -> SpokenConsentFlow {
        perception = FakePerception(); perception.tracks = [FakePerception.track(7), FakePerception.track(8, faceHeightPx: 120)]
        transcriber = FakeTranscriber(lines: [], clock: { [unowned self] in CACurrentMediaTime() - self.backdate }); speaker = LogSpeaker(simulateDuration: false); gate = CueGate()
        paths = .temporary(); store = JSONPeopleStore(paths: paths, modelID: "fake"); contacts = RecordingContactsBridge()
        recorder = AudioChunkClipRecorder(seconds: 60)
        let now = CACurrentMediaTime()
        recorder.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000 * 20), sampleRate: 16_000, timestamp: now - 10))
        var cfg = config ?? ConsentFlowConfig()
        if config == nil { cfg.listenTimeout = 1.5; cfg.reaskTimeout = 1; cfg.nameTimeout = 0.5; cfg.gatherTimeout = 0.5; cfg.extraGatherTimeout = 0.5; cfg.confirmTimeout = 1; cfg.numberTimeout = 1; cfg.numberSettle = 0.2; cfg.numberPause = 0.3 }
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

    func testEchoOfTheQuestionIsNotAnAnswer() async {
        let flow = makeFlow()
        speaker.simulateDuration = true; speaker.secondsPerWord = 0.05
        let run = Task { await flow.begin(confirmFirst: false) }
        await waitFor { [self] in isListening }
        // The recognizer finalizes the question's own audio a moment after it finished playing; "Okay to…" reads as yes.
        backdate = 0.6
        transcriber.emit(.init(speaker: .other, text: "Okay to remember your face, Marcus?"))
        backdate = 0
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(store.all().isEmpty, "the question itself must never count as consent")
        flow.cancel()
        await run.value
    }

    // MARK: Suggested: Poyo coaches the wearer, the wearer asks, only the other person's yes saves

    func testSuggestedCoachesWearerThenScanNameAndNumber() async throws {
        let flow = makeFlow(name: NameGuess(name: nil, confidence: 0, source: "regex"))
        let run = Task { await flow.begin(confirmFirst: true) }
        await waitFor { [self] in isListening }
        XCTAssertEqual(speaker.texts.first, Phrasebook.coachAskConsent)
        XCTAssertEqual(speaker.entries.first?.utterance.audience, .user, "coaching is only in the glasses")
        XCTAssertEqual(flow.lastQuestion, Phrasebook.wearerAsksCard(userName: "Priya"))
        XCTAssertTrue(gate.consentActive)
        // The wearer's own question, misattributed to the other side, is neither a yes nor a reason to re-ask.
        transcriber.emit(.init(speaker: .none, text: "Hey, do you want to be added to my contacts? It's okay if not."))
        transcriber.emit(.init(speaker: .other, text: "Hmm"))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertFalse(speaker.texts.contains(Phrasebook.wasThatAYes))
        transcriber.emit(.init(speaker: .other, text: "Yes, sure."))
        await waitFor { [self] in speaker.texts.contains(Phrasebook.coachAskName) }
        transcriber.emit(.init(speaker: .other, text: "Dana"))
        await waitFor { [self] in speaker.texts.contains(Phrasebook.coachAskNumber(name: "Dana")) }
        transcriber.emit(.init(speaker: .other, text: "Sure, it's five one two, 555"))
        transcriber.emit(.init(speaker: .other, text: "oh one oh oh"))
        await run.value
        guard case let .done(p)? = states.last else { return XCTFail("expected done, got \(String(describing: states.last))") }
        XCTAssertEqual(p.name, "Dana")
        XCTAssertEqual(p.phone, "(512) 555-0100")
        XCTAssertEqual(contacts.created.first?.phone, "(512) 555-0100")
        XCTAssertEqual(p.consent.kind, .spoken); XCTAssertEqual(p.consent.replyTranscript, "Yes, sure.")
        XCTAssertTrue(p.consent.askedText.hasPrefix("Asked by Priya:"), p.consent.askedText)
        XCTAssertEqual(speaker.texts, [Phrasebook.coachAskConsent, Phrasebook.coachAskName, Phrasebook.coachAskNumber(name: "Dana"),
                                       "Got 5 1 2, 5 5 5, 0 1 0 0.", Phrasebook.saved(name: "Dana")])
        XCTAssertTrue(speaker.entries.allSatisfy { $0.utterance.audience == .user }, "nothing is said to the other person by the app")
        XCTAssertFalse(gate.consentActive)
    }

    func testSuggestedKnownNameTapYesNoNumber() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: true) }
        await waitFor { [self] in isListening }
        flow.tapAnswer(yes: true)
        await run.value
        guard case let .done(p)? = states.last else { return XCTFail("expected done") }
        XCTAssertEqual(p.name, "Marcus"); XCTAssertEqual(p.consent.kind, .tap); XCTAssertNil(p.phone)
        XCTAssertFalse(speaker.texts.contains(Phrasebook.coachAskName))
        XCTAssertEqual(speaker.texts, [Phrasebook.coachAskConsent, Phrasebook.coachAskNumber(name: "Marcus"), Phrasebook.noNumber, Phrasebook.saved(name: "Marcus")])
    }

    func testSuggestedOtherSaysNoSavesNothing() async {
        let flow = makeFlow()
        let run = Task { await flow.begin(confirmFirst: true) }
        await waitFor { [self] in isListening }
        transcriber.emit(.init(speaker: .other, text: "No thanks."))
        await run.value
        XCTAssertEqual(states.last, .declined)
        XCTAssertTrue(store.all().isEmpty); XCTAssertTrue(contacts.created.isEmpty)
        XCTAssertFalse(speaker.texts.contains { $0.hasPrefix("Now ask") })
        XCTAssertEqual(speaker.texts.last, Phrasebook.nothingSaved)
    }

    func testSuggestedWithoutAnUnknownFaceDoesNothing() async {
        let flow = makeFlow()
        perception.tracks = []
        await flow.begin(confirmFirst: true)
        XCTAssertEqual(states.last, .idle)
        XCTAssertEqual(speaker.texts, [])
        XCTAssertFalse(gate.consentActive)
    }

    func testPhoneNumbersFromSpeech() {
        XCTAssertEqual(PhoneNumber.digits(in: "It's 512-555-0100."), "5125550100")
        XCTAssertEqual(PhoneNumber.digits(in: "five one two five five five oh one oh oh"), "5125550100")
        XCTAssertEqual(PhoneNumber.digits(in: "oh sure, it's (512) 555 0100"), "5125550100", "a leading 'oh' is not a zero")
        XCTAssertEqual(PhoneNumber.format("5125550100"), "(512) 555-0100")
        XCTAssertEqual(PhoneNumber.format("15125550100"), "+1 (512) 555-0100")
        XCTAssertEqual(PhoneNumber.format("4412345678901"), "4412345678901")
        XCTAssertEqual(Phrasebook.gotNumber("5125550100"), "Got 5 1 2, 5 5 5, 0 1 0 0.")
    }

    func testQuestionShapes() {
        XCTAssertTrue(SpokenConsentFlow.looksLikeQuestion("Do you want to be added to my contacts?"))
        XCTAssertTrue(SpokenConsentFlow.looksLikeQuestion("hey so would you mind if it remembers you"))
        XCTAssertTrue(SpokenConsentFlow.looksLikeQuestion("Is it okay if I add you"))
        XCTAssertFalse(SpokenConsentFlow.looksLikeQuestion("Yes, I want to be added"))
        XCTAssertFalse(SpokenConsentFlow.looksLikeQuestion("Sure, go ahead"))
    }
}
