import XCTest
@testable import Familiar

/// Scriptable conversation: the test decides when the agent is ready, what tool it calls and what it says.
@MainActor
final class FakeAgentConversation: AgentConversation {
    weak var delegate: AgentConversationDelegate?
    private(set) var isActive = true
    private(set) var messages: [String] = []
    private(set) var contexts: [String] = []
    private(set) var toolResults: [(id: String, result: String, isError: Bool)] = []
    private(set) var endCount = 0
    var readyImmediately = true

    func sendMessage(_ text: String) async throws { messages.append(text) }
    func updateContext(_ text: String) async throws { contexts.append(text) }
    func sendToolResult(id: String, result: String, isError: Bool) async throws { toolResults.append((id, result, isError)) }
    func end() async { isActive = false; endCount += 1 }
}

final class FakeAudioControl: AgentAudioControl {
    private(set) var pauses = 0
    private(set) var resumes = 0
    var running = true
    func pauseForAgent() { pauses += 1; running = false }
    func resumeAfterAgent() throws { resumes += 1; running = true }
}

@MainActor
final class AgentSessionTests: XCTestCase {
    var perception: FakePerception!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var flow: FakeConsentFlow!
    var store: JSONPeopleStore!
    var audio: FakeAudioControl!
    var streaming = false
    var conversations: [FakeAgentConversation] = []
    var requests: [AgentStartRequest] = []
    var failStart = false
    var session: AgentSession!
    let marcusID = UUID()

    override func setUp() async throws {
        perception = FakePerception(); speaker = LogSpeaker(simulateDuration: false); gate = CueGate(); flow = FakeConsentFlow(); audio = FakeAudioControl()
        store = JSONPeopleStore(paths: .temporary(), modelID: "fake")
        try store.add(makePerson(name: "Marcus", id: marcusID))
        let router = AgentToolRouter(perception: perception, peopleStore: store, contacts: RecordingContactsBridge(), consentFlow: flow, cueGate: gate, setMode: { _ in }, setMuted: { _ in })
        session = AgentSession(router: router, speaker: speaker, cueGate: gate, audio: audio, isStreaming: { [unowned self] in streaming },
                               agentID: { "agent_test" }, apiKey: { nil }, userName: { "Caleb" }, knownNames: { ["Marcus"] },
                               starter: { [unowned self] req, delegate in
                                   self.requests.append(req)
                                   if self.failStart { throw URLError(.notConnectedToInternet) }
                                   let c = FakeAgentConversation(); c.delegate = delegate
                                   self.conversations.append(c)
                                   if c.readyImmediately { Task { @MainActor in delegate.conversationReady() } }
                                   return c
                               },
                               config: AgentSessionConfig(idleTimeout: 0.15, maxDuration: 2, contextInterval: 0.05, readyTimeout: 0.5))
    }

    private func settle(_ seconds: TimeInterval = 0.05) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func waitUntil(_ timeout: TimeInterval = 1, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { await settle(0.01) }
    }

    func testLifecycleStartToolIdleEndRestartsEngine() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.9), band: .ahead, distance: .close), FakePerception.track(2), FakePerception.track(3)]
        await session.open(phrase: "how many people are around me")
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(audio.pauses, 1); XCTAssertFalse(audio.running)
        XCTAssertTrue(gate.consentActive, "routine cues are held while the agent owns the audio path")
        XCTAssertEqual(requests.first?.agentID, "agent_test")
        XCTAssertEqual(requests.first?.dynamicVariables["user_name"], "Caleb")
        XCTAssertEqual(requests.first?.dynamicVariables["known_names"], "Marcus")
        XCTAssertTrue(requests.first?.prompt.contains("at most 12 words") ?? false)
        let c = conversations[0]
        await waitUntil { c.messages == ["how many people are around me"] }
        XCTAssertEqual(c.messages, ["how many people are around me"], "phrase is sent as text right after onAgentReady")

        c.delegate?.conversationAgentState(.thinking)
        c.delegate?.conversationToolCall(AgentToolCall(id: "t1", name: "who_is_here"))
        await waitUntil { !c.toolResults.isEmpty }
        XCTAssertEqual(c.toolResults.first?.id, "t1")
        XCTAssertEqual(c.toolResults.first?.result, "Marcus, ahead, close. 2 other people.")
        XCTAssertEqual(c.toolResults.first?.isError, false)
        c.delegate?.conversationAgentState(.speaking)
        c.delegate?.conversationAgentSaid("Marcus ahead, close, and two others.")
        XCTAssertEqual(session.status, .speaking)
        c.delegate?.conversationAgentState(.listening)
        XCTAssertEqual(session.status, .listening)

        await waitUntil(1.5) { !self.session.isActive }
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.status, .ended(reason: "idle"))
        XCTAssertEqual(c.endCount, 1)
        XCTAssertEqual(audio.resumes, 1); XCTAssertTrue(audio.running, "engine restarted on Route A after the session")
        XCTAssertFalse(gate.consentActive)
        XCTAssertFalse(c.contexts.isEmpty, "scene context was pushed while live")
        XCTAssertEqual(c.contexts.first, "Visible now: Marcus ahead close; 2 other people.")
        XCTAssertTrue(session.transcript.contains { $0.role == .tool && $0.text.hasPrefix("who_is_here") })
        XCTAssertFalse(session.transcript.contains { $0.text.localizedCaseInsensitiveContains("familiar") })
    }

    func testRefusesWhileStreaming() async {
        streaming = true
        await session.open(phrase: "how many people are around me")
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(speaker.texts, ["Not while streaming."])
        XCTAssertEqual(conversations.count, 0, "no conversation is started")
        XCTAssertEqual(audio.pauses, 0, "engine untouched")
        XCTAssertEqual(session.refusedWhileStreaming, 1)
        XCTAssertEqual(session.status, .idle)
    }

    func testRememberThemEndsSessionThenBeginsConsent() async {
        await session.open(phrase: "remember them")
        let c = conversations[0]
        c.delegate?.conversationToolCall(AgentToolCall(id: "t2", name: "remember_them"))
        await waitUntil { self.flow.begins == [false] }
        XCTAssertEqual(c.toolResults.first?.result, "Starting.")
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(c.endCount, 1)
        XCTAssertEqual(session.status, .ended(reason: "tool remember_them"))
        XCTAssertEqual(flow.begins, [false])
        XCTAssertEqual(audio.resumes, 1, "the consent flow needs the engine back before it starts")
    }

    func testCancelEndsAndSecondPhraseIsFollowUp() async {
        await session.open(phrase: "where is Marcus")
        let c = conversations[0]
        await waitUntil { c.messages.count == 1 }
        await session.open(phrase: "and who else")
        XCTAssertEqual(c.messages, ["where is Marcus", "and who else"])
        XCTAssertEqual(conversations.count, 1)
        await session.cancel()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.status, .ended(reason: "cancelled"))
        XCTAssertEqual(audio.resumes, 1)
    }

    func testMaxDurationEndsSession() async {
        await session.open(phrase: "tell me a story")
        let c = conversations[0]
        c.delegate?.conversationAgentState(.speaking)       // never goes idle
        await waitUntil(3) { !self.session.isActive }
        XCTAssertEqual(session.status, .ended(reason: "max duration"))
        XCTAssertEqual(audio.resumes, 1)
    }

    func testStartFailureRestoresEngineAndSpeaksFallback() async {
        failStart = true
        await session.open(phrase: "hello")
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(audio.pauses, 1); XCTAssertEqual(audio.resumes, 1)
        XCTAssertEqual(speaker.texts, ["Assistant unavailable."])
        XCTAssertFalse(gate.consentActive)
    }

    func testSimulatedConversationRunsWholeLoop() async {
        perception.tracks = [FakePerception.track(2)]
        let router = AgentToolRouter(perception: perception, peopleStore: store, contacts: RecordingContactsBridge(), consentFlow: flow, cueGate: gate, setMode: { _ in }, setMuted: { _ in })
        let s = AgentSession(router: router, speaker: speaker, cueGate: gate, audio: audio, isStreaming: { false }, agentID: { "agent_test" }, apiKey: { nil },
                             userName: { "Caleb" }, knownNames: { [] }, starter: SimulatedAgentConversation.starter,
                             config: AgentSessionConfig(idleTimeout: 0.1, maxDuration: 2, contextInterval: 1, readyTimeout: 1))
        await s.open(phrase: "how many people are around me")
        await waitUntil(1.5) { !s.isActive }
        XCTAssertEqual(s.status, .ended(reason: "idle"))
        XCTAssertTrue(s.transcript.contains { $0.role == .agent && $0.text == "No one I know. 1 person." || $0.role == .agent && $0.text == Phrasebook.rollCallNoKnown(count: 1) })
        XCTAssertEqual(audio.resumes, 1)
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
        source.wakeWord.feed(text: "Familiar, who is here", isFinal: true, t: 1)
        source.wakeWord.feed(text: "Familiar, how many people are around me", isFinal: true, t: 10)
        await settle(0.1)
        source.wakeWord.tick(now: 30)
        await waitUntil { got.count == 1 && parsed.count == 1 }
        t.cancel(); t2.cancel()
        XCTAssertEqual(parsed, [.whoIsHere])
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got.first?.lowercased().contains("how many people") ?? false, "\(got)")
        XCTAssertFalse(got.first?.lowercased().contains("familiar") ?? true, "wake word is stripped from the phrase")
    }
}
