import XCTest
@testable import Familiar

/// Scriptable conversation: the test decides what tool the agent calls and what it says.
@MainActor
final class FakeAgentConversation: AgentConversation {
    weak var delegate: AgentConversationDelegate?
    private(set) var isActive = true
    private(set) var messages: [String] = []
    private(set) var contexts: [String] = []
    private(set) var toolResults: [(id: String, result: String, isError: Bool)] = []
    private(set) var endCount = 0

    func sendMessage(_ text: String) async throws { messages.append(text) }
    func updateContext(_ text: String) async throws { contexts.append(text) }
    func sendToolResult(id: String, result: String, isError: Bool) async throws { toolResults.append((id, result, isError)) }
    func end() async { isActive = false; endCount += 1 }
}

@MainActor
final class AgentSessionTests: XCTestCase {
    var perception: FakePerception!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var flow: FakeConsentFlow!
    var store: JSONPeopleStore!
    var transcriber: FakeTranscriber!
    var conversations: [FakeAgentConversation] = []
    var requests: [AgentStartRequest] = []
    var failStart = false
    var consent = false
    var session: AgentSession!
    let marcusID = UUID()

    override func setUp() async throws {
        perception = FakePerception(); speaker = LogSpeaker(simulateDuration: false); gate = CueGate(); flow = FakeConsentFlow()
        transcriber = FakeTranscriber(lines: [])
        store = JSONPeopleStore(paths: .temporary(), modelID: "fake")
        try store.add(makePerson(name: "Marcus", id: marcusID))
        let router = AgentToolRouter(perception: perception, peopleStore: store, contacts: RecordingContactsBridge(), consentFlow: flow, cueGate: gate, setMode: { _ in }, setMuted: { _ in })
        session = AgentSession(router: router, speaker: speaker, cueGate: gate, agentID: { "agent_test" }, apiKey: { nil }, userName: { "Caleb" }, knownNames: { ["Marcus"] },
                               starter: { [unowned self] req, delegate in
                                   self.requests.append(req)
                                   if self.failStart { throw URLError(.notConnectedToInternet) }
                                   let c = FakeAgentConversation(); c.delegate = delegate
                                   self.conversations.append(c)
                                   return c
                               },
                               config: AgentSessionConfig(contextInterval: 0.05, reconnectDelays: [0.05]))
        session.consentActive = { [unowned self] in consent }
    }

    override func tearDown() async throws { await session.stop() }

    private func settle(_ seconds: TimeInterval = 0.05) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func waitUntil(_ timeout: TimeInterval = 1, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { await settle(0.01) }
    }

    private func startLive() async -> FakeAgentConversation? {
        session.start(speech: transcriber.subscribe())
        await waitUntil { self.session.status == .live }
        return conversations.last
    }

    func testOpensAtStartAndPushesChangedContextOnly() async throws {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.9), band: .ahead, distance: .close), FakePerception.track(2), FakePerception.track(3)]
        let live = await startLive(); let c = try XCTUnwrap(live)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(requests.first?.agentID, "agent_test")
        XCTAssertEqual(requests.first?.dynamicVariables["user_name"], "Caleb")
        XCTAssertEqual(requests.first?.dynamicVariables["known_names"], "Marcus")
        XCTAssertTrue(requests.first?.prompt.contains("at most 12 words") ?? false)
        XCTAssertEqual(c.contexts.first, "Visible now: Marcus 12 o'clock close; 2 other people.")
        await settle(0.2)
        XCTAssertEqual(c.contexts.count, 1, "unchanged context is not re-sent")
        perception.tracks = []
        await waitUntil { c.contexts.count == 2 }
        XCTAssertEqual(c.contexts.last, "Visible now: no one.")
    }

    func testWearerSpeechIsATurnOtherSpeechIsContextWakeWordIsNeither() async throws {
        let live = await startLive(); let c = try XCTUnwrap(live)
        transcriber.emit(.init(speaker: .user, text: "where did I put my keys"))
        transcriber.emit(.init(speaker: .other, text: "I'm Dana, by the way"))
        transcriber.emit(.init(speaker: .user, text: "Poyo, mute"))
        await waitUntil { c.contexts.contains("Other person said: I'm Dana, by the way") }
        await settle()
        XCTAssertEqual(c.messages, ["[overheard] where did I put my keys"])
        XCTAssertTrue(c.contexts.contains("Other person said: I'm Dana, by the way"))
    }

    func testSkipStaysSilentAnswersInterruptRemarksObeyMute() async throws {
        let live = await startLive(); let c = try XCTUnwrap(live)
        c.delegate?.conversationAgentSaid("SKIP")
        await session.ask("how many people are around me")
        XCTAssertEqual(c.messages.last, "[to you] how many people are around me")
        c.delegate?.conversationAgentSaid("Three people, Marcus ahead.")
        await waitUntil { !self.speaker.texts.isEmpty }
        XCTAssertEqual(speaker.texts, ["Three people, Marcus ahead."])
        XCTAssertEqual(speaker.entries.last?.utterance.priority, 0)
        gate.muted = true
        c.delegate?.conversationAgentSaid("Marcus is behind you.")
        c.delegate?.conversationAgentSaid("Poyo, can see two chairs.")
        await settle()
        XCTAssertEqual(speaker.texts, ["Three people, Marcus ahead."], "unsolicited remarks obey mute")
        XCTAssertTrue(session.transcript.contains { $0.role == .agent && $0.text == "Can see two chairs." })
    }

    func testConsentHoldsTheAgent() async throws {
        let live = await startLive(); let c = try XCTUnwrap(live)
        consent = true
        transcriber.emit(.init(speaker: .user, text: "do you want to be added to my contacts"))
        transcriber.emit(.init(speaker: .other, text: "yes sure"))
        await settle(0.1)
        XCTAssertTrue(c.messages.isEmpty); XCTAssertFalse(c.contexts.contains { $0.contains("yes sure") })
        c.delegate?.conversationAgentSaid("Sure!")
        await settle()
        XCTAssertTrue(speaker.texts.isEmpty, "the agent never speaks over a consent exchange")
    }

    func testToolCallIsAnswered() async throws {
        perception.tracks = [FakePerception.track(2)]
        let live = await startLive(); let c = try XCTUnwrap(live)
        c.delegate?.conversationToolCall(AgentToolCall(id: "t1", name: "who_is_here"))
        await waitUntil { !c.toolResults.isEmpty }
        XCTAssertEqual(c.toolResults.first?.id, "t1")
        XCTAssertEqual(c.toolResults.first?.result, Phrasebook.rollCallNoKnown(count: 1))
        XCTAssertTrue(session.transcript.contains { $0.role == .tool && $0.text.hasPrefix("who_is_here") })
    }

    func testReconnectsAfterDisconnectAndFailure() async throws {
        let live = await startLive(); let c = try XCTUnwrap(live)
        failStart = true
        c.delegate?.conversationDisconnected()
        XCTAssertFalse(session.isActive)
        await waitUntil { self.requests.count >= 3 }
        XCTAssertEqual(session.status, .ended(reason: "connect failed"))
        failStart = false
        await waitUntil { self.session.status == .live }
        XCTAssertEqual(conversations.count, 2)
        XCTAssertEqual(session.sessionsOpened, 2)
    }

    func testRecentSpeechIsReplayedOnConnect() async throws {
        session.recentSpeech = { [TranscriptSegment(text: "I'm Dana", start: 0, end: 1, isFinal: true, speaker: .other), TranscriptSegment(text: "nice to meet you", start: 1, end: 2, isFinal: true, speaker: .user)] }
        let live = await startLive(); let c = try XCTUnwrap(live)
        XCTAssertEqual(c.contexts.first, "Speech so far:\nOther person: I'm Dana\nWearer: nice to meet you")
    }

    func testAskWhileDisconnectedSaysUnavailable() async {
        await session.ask("what's the time")
        XCTAssertEqual(speaker.texts, [Phrasebook.assistantUnavailable])
    }

    func testSimulatedConversationRunsWholeLoop() async {
        perception.tracks = [FakePerception.track(2)]
        let router = AgentToolRouter(perception: perception, peopleStore: store, contacts: RecordingContactsBridge(), consentFlow: flow, cueGate: gate, setMode: { _ in }, setMuted: { _ in })
        let s = AgentSession(router: router, speaker: speaker, cueGate: gate, agentID: { "agent_test" }, apiKey: { nil },
                             userName: { "Caleb" }, knownNames: { [] }, starter: SimulatedAgentConversation.starter,
                             config: AgentSessionConfig(contextInterval: 0.05, reconnectDelays: [0.05]))
        s.start(speech: transcriber.subscribe())
        await waitUntil { s.status == .live }
        transcriber.emit(.init(speaker: .user, text: "so anyway"))
        await s.ask("how many people are around me")
        await waitUntil { !self.speaker.texts.isEmpty }
        XCTAssertEqual(speaker.texts, [Phrasebook.rollCallNoKnown(count: 1)], "overheard small talk is skipped, the question is answered")
        await s.stop()
    }

    func testUnparsedWakeWordPhrasesFallThrough() async {
        let source = WakeWordCommandSource()
        var got: [String] = []
        let stream = source.subscribeUnparsed()
        let commands = source.subscribe()
        let t = Task { for await p in stream { got.append(p); if got.count == 1 { break } } }
        var parsed: [Command] = []
        let t2 = Task { for await c in commands { parsed.append(c); break } }
        await settle(0.02)
        source.wakeWord.feed(text: "Poyo, who is here", isFinal: true, t: 1)
        source.wakeWord.feed(text: "Poyo, how many people are around me", isFinal: true, t: 10)
        await settle(0.1)
        source.wakeWord.tick(now: 30)
        await waitUntil { got.count == 1 && parsed.count == 1 }
        t.cancel(); t2.cancel()
        XCTAssertEqual(parsed, [.whoIsHere])
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got.first?.lowercased().contains("how many people") ?? false, "\(got)")
        XCTAssertFalse(got.first?.lowercased().contains("poyo") ?? true, "wake word is stripped from the phrase")
    }
}
