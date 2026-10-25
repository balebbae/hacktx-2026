import XCTest
@testable import Familiar

@MainActor
final class CommandRouterTests: XCTestCase {
    var perception: FakePerception!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var flow: FakeConsentFlow!
    var store: JSONPeopleStore!
    var contacts: RecordingContactsBridge!
    var modes: [ChatterMode] = []
    var mutes: [Bool] = []
    var now: TimeInterval = 1000
    var router: CommandRouter!
    let marcusID = UUID()

    override func setUp() async throws {
        perception = FakePerception(); speaker = LogSpeaker(simulateDuration: false); gate = CueGate(); flow = FakeConsentFlow()
        store = JSONPeopleStore(paths: .temporary(), modelID: "fake"); contacts = RecordingContactsBridge()
        var p = makePerson(name: "Marcus", id: marcusID); p.phone = "+1 (512) 555-0100"; try store.add(p)
        router = CommandRouter(perception: perception, speaker: speaker, cueGate: gate, consentFlow: flow, peopleStore: store, contacts: contacts,
                               setMode: { [unowned self] in modes.append($0) }, setMuted: { [unowned self] in mutes.append($0) }, clock: { [unowned self] in now })
    }

    func testWhoIsHereSpeaksRollCall() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .left, distance: .medium), FakePerception.track(2)]
        await router.handle(.whoIsHere)
        XCTAssertEqual(speaker.texts.last, "Marcus, 12 o'clock, medium. One other person.")
    }

    func testModesAndMute() async {
        await router.handle(.setMode(.chatty)); await router.handle(.mute); await router.handle(.unmute)
        XCTAssertEqual(modes, [.chatty]); XCTAssertEqual(mutes, [true, false]); XCTAssertFalse(gate.muted)
        XCTAssertEqual(speaker.texts.suffix(3), ["Chatty mode.", "Muted.", "Unmuted."])
    }

    func testCallAndTextByPrefixOpenSystemUIOnly() async {
        await router.handle(.call("mar")); await router.handle(.text("MARC")); await router.handle(.call("dana"))
        XCTAssertEqual(contacts.called.map(\.name), ["Marcus"]); XCTAssertEqual(contacts.texted.map(\.name), ["Marcus"])
        XCTAssertEqual(speaker.texts.suffix(3), ["Calling Marcus.", "Opening a message to Marcus.", "I don't know anyone called dana."])
    }

    func testWhereIsUsesTracksThenLastSeen() async {
        await router.handle(.whereIs("marcus"))
        XCTAssertEqual(speaker.texts.last, "I don't see Marcus.")
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .right, distance: .far)]
        await router.handle(.whereIs("marcus"))
        XCTAssertEqual(speaker.texts.last, "Marcus, 12 o'clock, far.")
        router.startObserving()
        perception.publish(.knownLeft(personID: marcusID, name: "Marcus", last: Bearing(degrees: -40, band: .farLeft)))
        perception.tracks = []
        try? await Task.sleep(nanoseconds: 100_000_000)
        await router.handle(.whereIs("mar"))
        XCTAssertEqual(speaker.texts.last, Phrasebook.lastSeen(name: "Marcus", bearing: Bearing(degrees: -40, band: .farLeft)))
        router.stop()
    }

    func testRememberCancelRepeat() async {
        await router.handle(.rememberThem)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(flow.begins, [false])
        await router.handle(.cancel)
        XCTAssertEqual(flow.cancels, 1)
        await router.handle(.setMode(.quiet))
        let n = speaker.texts.count
        await router.handle(.repeatLast)
        XCTAssertEqual(speaker.texts.count, n + 1); XCTAssertEqual(speaker.texts.last, "Quiet mode.")
    }

    func testGoodbyeNeedsCloseStrangerAndCooldown() async {
        router.goodbyeCooldown = 60
        await router.goodbyeDetected(at: now)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(flow.begins, [], "no stranger close")
        perception.tracks = [FakePerception.track(3, distance: .close)]
        await router.goodbyeDetected(at: now)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(flow.begins, [true])
        await router.goodbyeDetected(at: now + 10)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(flow.begins, [true], "cooldown")
        await router.goodbyeDetected(at: now + 61)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(flow.begins, [true, true])
    }

    func testDescribeSurroundingsSpeaksHazardsPeopleThenPlace() async {
        router.surroundings = { people in ["Stairs ahead.", people, "Kitchen."].compactMap { $0 }.joined(separator: " ") }
        await router.handle(.describeSurroundings)
        XCTAssertEqual(speaker.texts.last, "Stairs ahead. Kitchen.", "no people line when nobody is in view")
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .ahead, distance: .close)]
        await router.handle(.describeSurroundings)
        XCTAssertEqual(speaker.texts.last, "Stairs ahead. Marcus, 12 o'clock, close. No one else. Kitchen.")
    }

    func testConversationWindowNeedsBothSides() {
        var w = ConversationWindow(); w.words = 10
        func seg(_ t: TimeInterval, _ s: SpeakerGuess, _ words: Int) -> TranscriptSegment {
            TranscriptSegment(text: Array(repeating: "word", count: words).joined(separator: " "), start: t - 1, end: t, isFinal: true, speaker: s)
        }
        XCTAssertFalse(w.add(seg(1, .user, 8)))
        XCTAssertFalse(w.add(seg(2, .user, 8)), "a monologue is not a conversation")
        XCTAssertTrue(w.add(seg(3, .other, 2)))
        XCTAssertFalse(w.add(seg(4, .other, 20)), "starts over after firing")
        XCTAssertFalse(w.add(seg(100, .user, 3)), "old words fall out of the window")
    }

    func testManualCommandSourceIsRouted() async {
        let src = ManualCommandSource()
        router.attach(sources: [src])
        src.send(.setMode(.normal))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(modes, [.normal])
        router.stop()
    }
}
