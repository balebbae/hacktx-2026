import XCTest
@testable import Familiar

/// S10: the other person enrolls themselves on the phone. Fake pipeline, temp JSON store, recording contacts bridge.
@MainActor
final class SelfEnrollTests: XCTestCase {
    var paths: MemoryPaths!
    var store: JSONPeopleStore!
    var contacts: RecordingContactsBridge!
    var perception: FakePerception!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var began = 0
    var ended = 0

    override func setUp() async throws {
        paths = .temporary(); store = JSONPeopleStore(paths: paths, modelID: "fake"); contacts = RecordingContactsBridge()
        perception = FakePerception(); perception.embeddingsPerTrack = 6
        perception.tracks = [FakePerception.track(1)]
        speaker = LogSpeaker(simulateDuration: false); gate = CueGate()
        began = 0; ended = 0
    }

    func makeModel(target: Int = 8, minimum: Int = 5) -> SelfEnrollModel {
        var cfg = SelfEnrollModel.Config.default
        cfg.targetEmbeddings = target; cfg.minEmbeddings = minimum; cfg.pollInterval = 0.01
        return SelfEnrollModel(perception: perception, frames: SilentFrameSource(), store: store, contacts: contacts, speaker: speaker, cueGate: gate, meeting: StaticMeetingContext(placeName: "HackTX"), userName: "Priya", config: cfg,
                               onBegin: { [self] in began += 1 }, onEnd: { [self] in ended += 1 })
    }

    /// Drives a model to the consent screen with the fake pipeline.
    func reachConsent(_ m: SelfEnrollModel, name: String = "Marcus") async {
        await m.beginScan()
        try? await Task.sleep(nanoseconds: 150_000_000)
        m.finishScan()
        m.name = name
        m.submitName()
    }

    func testCollectsEmbeddingsFromFakePipelineAndAdvancesAtTarget() async throws {
        let m = makeModel(target: 6, minimum: 5)
        XCTAssertEqual(m.step, .intro)
        await m.beginScan()
        XCTAssertEqual(m.step, .scanning)
        XCTAssertEqual(began, 1)
        XCTAssertTrue(gate.consentActive, "cues pause while a stranger is at the phone")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(m.collected, 6)
        XCTAssertEqual(m.gathered.count, 6)
        XCTAssertEqual(m.step, .name, "auto-advances once the target is reached")
        XCTAssertFalse(perception.bursts.isEmpty)
        XCTAssertEqual(m.hint, Phrasebook.scanProgress(6, of: 6))
        XCTAssertEqual(speaker.texts, [Phrasebook.someoneIntroducing], "the wearer only hears the heads-up, never the stranger's name")
    }

    func testNextStaysLockedBelowMinimum() async throws {
        perception.embeddingsPerTrack = 3
        let m = makeModel(target: 8, minimum: 5)
        await m.beginScan()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(m.collected, 3)
        XCTAssertFalse(m.canContinueScan)
        m.finishScan()
        XCTAssertEqual(m.step, .scanning)
        await m.cancel()
    }

    func testNothingSavedWithoutTapYes() async throws {
        let m = makeModel()
        await reachConsent(m)
        XCTAssertEqual(m.step, .consent)
        XCTAssertTrue(store.all().isEmpty, "reaching the consent screen writes nothing")
        XCTAssertTrue(contacts.created.isEmpty)
        await m.answer(yes: false)
        XCTAssertEqual(m.step, .cancelled)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(contacts.created.isEmpty)
        XCTAssertEqual(m.gathered.count, 0)
        XCTAssertFalse(gate.consentActive)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(speaker.texts.last, Phrasebook.nothingSaved)
        XCTAssertFalse(speaker.texts.contains { $0.contains("Marcus") }, "no name is spoken without a YES")
        let thumbs = try? FileManager.default.contentsOfDirectory(atPath: paths.thumbsDir.path)
        XCTAssertTrue(thumbs?.isEmpty ?? true)
    }

    func testCancelMidScanSavesNothing() async throws {
        let m = makeModel()
        await m.beginScan()
        try await Task.sleep(nanoseconds: 50_000_000)
        await m.cancel()
        XCTAssertEqual(m.step, .cancelled)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(m.collected, 0)
        XCTAssertEqual(ended, 1)
        await m.beginScan()
        XCTAssertEqual(m.step, .cancelled, "a cancelled model does not restart")
    }

    func testTapYesSavesTapConsentPersonWithThumbnailAndContact() async throws {
        let m = makeModel()
        await reachConsent(m, name: "  Marcus ")
        m.phone = "512 555 0100"
        XCTAssertEqual(m.consentText, "Okay to remember your face, Marcus? Only this phone keeps it. You can be removed any time.")
        await m.answer(yes: true)
        guard case let .done(saved) = m.step else { return XCTFail("expected done, got \(m.step)") }
        XCTAssertEqual(saved.name, "Marcus")
        XCTAssertEqual(saved.phone, "512 555 0100")
        XCTAssertEqual(saved.consent.kind, .tap)
        XCTAssertEqual(saved.consent.askedText, m.consentText)
        XCTAssertNil(saved.consent.clipURL)
        XCTAssertEqual(saved.embeddings.count, 6)
        XCTAssertEqual(saved.contactIdentifier, "fake-\(saved.id.uuidString)")
        XCTAssertEqual(contacts.created.map(\.name), ["Marcus"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: saved.id).path), "thumbnail from the best embedding")
        XCTAssertEqual(perception.assigned.map(\.name), ["Marcus"])
        // Persisted, not just in memory; and the gallery serves it for recognition.
        let again = JSONPeopleStore(paths: paths, modelID: "fake")
        XCTAssertEqual(again.all().map(\.name), ["Marcus"])
        XCTAssertEqual(again.gallery().people.first?.embeddings.count, 6)
        XCTAssertEqual(m.doneText, "Saved. Marcus, hand the phone back.")
        XCTAssertEqual(speaker.texts, [Phrasebook.someoneIntroducing, "Saved. Marcus is in your contacts."])
        XCTAssertFalse(gate.consentActive)
        XCTAssertEqual(ended, 1)
        await m.close()
        XCTAssertEqual(ended, 1, "end hook fires once")
    }

    func testRemovalDeletesFilesAndContact() async throws {
        let m = makeModel()
        await reachConsent(m)
        await m.answer(yes: true)
        guard case let .done(saved) = m.step else { return XCTFail("expected done") }
        let thumb = paths.thumbnailURL(for: saved.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumb.path))
        let removing = JSONPeopleStore(paths: paths, modelID: "fake", contacts: contacts)
        try removing.remove(id: saved.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(removing.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumb.path))
        XCTAssertEqual(contacts.deleted, [saved.contactIdentifier!])
        XCTAssertEqual(removing.gallery().people.count, 0)
    }

    func testURLRouteOpensTheFlow() {
        XCTAssertEqual(AppRoute(url: URL(string: "familiar://introduce")!), .introduce)
        XCTAssertEqual(AppRoute(url: URL(string: "familiar:///introduce")!), .introduce)
        XCTAssertEqual(AppRoute(url: URL(string: "FAMILIAR://Introduce")!), .introduce)
        XCTAssertNil(AppRoute(url: URL(string: "familiar://glasses-callback")!))
        XCTAssertNil(AppRoute(url: URL(string: "https://example.com/introduce")!))
        let coordinator = AppCoordinator()
        XCTAssertNil(coordinator.pendingRoute)
        coordinator.handle(url: URL(string: "familiar://introduce")!)
        XCTAssertEqual(coordinator.pendingRoute, .introduce, "HomeView observes pendingRoute and presents SelfEnrollView")
        coordinator.pendingRoute = nil
        coordinator.handle(url: URL(string: "familiar://something-else")!)
        XCTAssertNil(coordinator.pendingRoute)
    }

    func testNFCRecordsYieldTheIntroduceURL() {
        let uri = Data("familiar://introduce".utf8)
        XCTAssertEqual(NFCTagReader.url(fromRecords: [(0x01, Data("U".utf8), Data([0x00]) + uri)])?.absoluteString, "familiar://introduce")
        let text = Data([0x02]) + Data("en".utf8) + uri
        XCTAssertEqual(NFCTagReader.url(fromRecords: [(0x01, Data("T".utf8), text)])?.absoluteString, "familiar://introduce")
        XCTAssertEqual(NFCTagReader.url(fromRecords: [(0x01, Data("U".utf8), Data([0x04]) + Data("github.com/x".utf8))])?.absoluteString, "https://github.com/x")
        XCTAssertNil(NFCTagReader.url(fromRecords: [(0x01, Data("T".utf8), Data([0x02]) + Data("enhello".utf8))]))
        XCTAssertNil(NFCTagReader.url(fromRecords: []))
    }

    func testWordingIsStrangerSafe() {
        let m = makeModel()
        XCTAssertEqual(m.introText, "Priya uses this app to recognize people who agree. Want them to remember you?")
        for s in [Phrasebook.someoneIntroducing, m.introText, Phrasebook.selfEnrollConsent(name: "Marcus"), Phrasebook.selfEnrollHandBack(name: "Marcus"), Phrasebook.scanProgress(6, of: 8), Phrasebook.noFaceYet] {
            XCTAssertFalse(s.localizedCaseInsensitiveContains("familiar"), "\(s) must not contain the wake word")
        }
        XCTAssertFalse(Phrasebook.someoneIntroducing.contains("Marcus"))
        XCTAssertTrue(Phrasebook.selfEnrollConsent(name: "Marcus").contains("Only this phone keeps it"))
        XCTAssertTrue(Phrasebook.selfEnrollConsent(name: "Marcus").contains("removed any time"))
    }
}
