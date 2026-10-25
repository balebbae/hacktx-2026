import XCTest
@testable import Familiar

@MainActor
final class AgentToolRouterTests: XCTestCase {
    var perception: FakePerception!
    var gate: CueGate!
    var flow: FakeConsentFlow!
    var store: JSONPeopleStore!
    var contacts: RecordingContactsBridge!
    var modes: [ChatterMode] = []
    var mutes: [Bool] = []
    var lastSeen: [UUID: LastSeen] = [:]
    var router: AgentToolRouter!
    let marcusID = UUID()

    override func setUp() async throws {
        perception = FakePerception(); gate = CueGate(); flow = FakeConsentFlow(); contacts = RecordingContactsBridge()
        store = JSONPeopleStore(paths: .temporary(), modelID: "fake")
        var p = makePerson(name: "Marcus", id: marcusID); p.phone = "+1 (512) 555-0100"; try store.add(p)
        router = AgentToolRouter(perception: perception, peopleStore: store, contacts: contacts, consentFlow: flow, cueGate: gate,
                                 setMode: { [unowned self] in modes.append($0) }, setMuted: { [unowned self] in mutes.append($0) },
                                 lastSeen: { [unowned self] in lastSeen })
    }

    func testToolNamesMatchDashboardList() {
        XCTAssertEqual(AgentToolRouter.toolNames, ["who_is_here", "where_is", "describe_surroundings", "remember_them", "set_mode", "call_person", "text_person", "mute"])
    }

    func testWhoIsHereReturnsRollCallText() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .left, distance: .medium), FakePerception.track(2)]
        let r = await router.handle(AgentToolCall(name: "who_is_here"))
        XCTAssertEqual(r.text, RollCall.phrase(tracks: perception.tracks))
        XCTAssertEqual(r.text, "Marcus, 12 o'clock, medium. One other person.")
        XCTAssertFalse(r.isError)
    }

    func testWhoIsHereEmptyRoom() async {
        let r = await router.handle(AgentToolCall(name: "who_is_here"))
        XCTAssertEqual(r.text, Phrasebook.nobody)
    }

    func testWhereIsUnknownName() async {
        let r = await router.handle(AgentToolCall(name: "where_is", parameters: ["name": "Zed"]))
        XCTAssertEqual(r.text, "I don't know anyone called Zed.")
    }

    func testWhereIsVisibleThenLastSeenThenNotVisible() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .right, distance: .close)]
        var r = await router.handle(AgentToolCall(name: "where_is", parameters: ["name": "marcus"]))
        XCTAssertEqual(r.text, "Marcus, 12 o'clock, close.")
        perception.tracks = []
        lastSeen[marcusID] = LastSeen(name: "Marcus", personID: marcusID, bearing: Bearing(degrees: -30, band: .left), at: 1)
        r = await router.handle(AgentToolCall(name: "where_is", parameters: ["name": "Marcus"]))
        XCTAssertEqual(r.text, Phrasebook.lastSeen(name: "Marcus", bearing: Bearing(degrees: -30, band: .left)))
        lastSeen = [:]
        r = await router.handle(AgentToolCall(name: "where_is", parameters: ["name": "Marcus"]))
        XCTAssertEqual(r.text, "I don't see Marcus.")
    }

    func testWhereIsWithoutNameIsError() async {
        let r = await router.handle(AgentToolCall(name: "where_is"))
        XCTAssertTrue(r.isError)
    }

    func testRememberThemStartsTheAppAskedConsentFlow() async {
        let r = await router.handle(AgentToolCall(name: "remember_them"))
        XCTAssertEqual(r.text, "Asking them now.")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(flow.begins, [false], "the app asks the other person itself; the agent never decides consent")
    }

    func testDescribeSurroundingsPutsPeopleAfterHazards() async {
        router.surroundings = { people in "Stairs ahead. " + (people ?? "") + " Kitchen." }
        perception.tracks = [FakePerception.track(2)]
        let r = await router.handle(AgentToolCall(name: "describe_surroundings"))
        XCTAssertEqual(r.text, "Stairs ahead. No one I know. 1 person. Kitchen.")
        XCTAssertTrue(router.sceneContext().hasSuffix("Around: Stairs ahead.  Kitchen."), router.sceneContext())
    }

    func testSetModeMapsWords() async {
        var r = await router.handle(AgentToolCall(name: "set_mode", parameters: ["mode": "quiet"]))
        XCTAssertEqual(r.text, "Quiet mode.")
        r = await router.handle(AgentToolCall(name: "set_mode", parameters: ["mode": "Chatty."]))
        XCTAssertEqual(r.text, "Chatty mode.")
        r = await router.handle(AgentToolCall(name: "set_mode", parameters: ["mode": "normal"]))
        XCTAssertEqual(r.text, "Normal mode.")
        XCTAssertEqual(modes, [.quiet, .chatty, .normal])
        r = await router.handle(AgentToolCall(name: "set_mode", parameters: ["mode": "loud"]))
        XCTAssertTrue(r.isError)
        XCTAssertEqual(modes.count, 3)
    }

    func testCallAndTextOpenSystemUIOnly() async {
        var r = await router.handle(AgentToolCall(name: "call_person", parameters: ["name": "Marcus"]))
        XCTAssertEqual(r.text, "Calling Marcus.")
        XCTAssertEqual(contacts.called.map(\.id), [marcusID])
        r = await router.handle(AgentToolCall(name: "text_person", parameters: ["name": "marc"]))
        XCTAssertEqual(r.text, "Opening a message to Marcus.")
        XCTAssertEqual(contacts.texted.map(\.id), [marcusID])
        r = await router.handle(AgentToolCall(name: "call_person", parameters: ["name": "Zed"]))
        XCTAssertEqual(r.text, "I don't know anyone called Zed.")
        r = await router.handle(AgentToolCall(name: "text_person", parameters: ["name": "Zed"]))
        XCTAssertEqual(r.text, "I don't know anyone called Zed.")
        XCTAssertEqual(contacts.called.count, 1); XCTAssertEqual(contacts.texted.count, 1)
    }

    func testMuteSetsGateAndState() async {
        let r = await router.handle(AgentToolCall(name: "mute"))
        XCTAssertEqual(r.text, "Muted.")
        XCTAssertTrue(gate.muted)
        XCTAssertEqual(mutes, [true])
    }

    func testUnknownToolIsError() async {
        let r = await router.handle(AgentToolCall(name: "describe_faces"))
        XCTAssertTrue(r.isError)
    }

    func testSceneContextCountsStrangersOnly() {
        let tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.8), band: .ahead, distance: .close), FakePerception.track(2), FakePerception.track(3)]
        XCTAssertEqual(AgentToolRouter.sceneContext(tracks: tracks), "Visible now: Marcus 12 o'clock close; 2 other people.")
        XCTAssertEqual(AgentToolRouter.sceneContext(tracks: []), "Visible now: no one.")
        XCTAssertEqual(AgentToolRouter.sceneContext(tracks: [FakePerception.track(2)]), "Visible now: 1 other person.")
    }

    func testNoResultMentionsWakeWord() async {
        perception.tracks = [FakePerception.track(2)]
        for name in AgentToolRouter.toolNames {
            let r = await router.handle(AgentToolCall(name: name, parameters: ["name": "Marcus", "mode": "quiet"]))
            XCTAssertFalse(r.text.localizedCaseInsensitiveContains("familiar"), name)
        }
    }
}
