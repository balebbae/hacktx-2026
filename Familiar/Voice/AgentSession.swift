import Foundation
import QuartzCore
import os
#if canImport(ElevenLabs)
import ElevenLabs
#endif

// S8 — on-demand ElevenLabs conversational agent. Never always-on: a session opens only for an unparsed
// "Familiar, …" phrase (or a button), answers, and ends by itself after the answer + 8 s idle, 90 s total,
// a cancel, or the `remember_them` tool. The audio engine is paused for the session and restarted on Route A.

enum AgentActivity: Equatable { case listening, speaking, thinking }

/// What `AgentSession` needs from a live conversation. `LiveAgentConversation` wraps the SDK; tests use a fake.
@MainActor
protocol AgentConversation: AnyObject {
    var isActive: Bool { get }
    func sendMessage(_ text: String) async throws
    func updateContext(_ text: String) async throws
    func sendToolResult(id: String, result: String, isError: Bool) async throws
    func end() async
}

/// Callbacks a conversation delivers back into the session (all on the main actor).
@MainActor
protocol AgentConversationDelegate: AnyObject {
    func conversationReady()
    func conversationAgentState(_ s: AgentActivity)
    func conversationAgentSaid(_ text: String)
    func conversationUserSaid(_ text: String)
    func conversationToolCall(_ call: AgentToolCall)
    func conversationDisconnected()
}

struct AgentStartRequest {
    let agentID: String
    let apiKey: String?
    let prompt: String
    let dynamicVariables: [String: String]
}

typealias AgentConversationStarter = @MainActor (AgentStartRequest, AgentConversationDelegate) async throws -> AgentConversation

/// The audio engine, as the session sees it: silence it before the agent takes the mic, bring it back on Route A after.
protocol AgentAudioControl: AnyObject {
    func pauseForAgent()
    func resumeAfterAgent() throws
}

extension AudioEngineController: AgentAudioControl {
    func pauseForAgent() { suspendedForAgent = true; stopEngine() }
    func resumeAfterAgent() throws { suspendedForAgent = false; try setRoute(.phoneMicGlassesA2DP) }
}

extension Phrasebook {
    static let notWhileStreaming = "Not while streaming."
    static let assistantUnavailable = "Assistant unavailable."
    /// App-side prompt override so the demo works even if the dashboard still has the default prompt.
    static let agentSystemPrompt = """
    You are a terse assistant for a blind wearer. Answer in at most 12 words. \
    Use the client tools for anything about the room or the people in it: who_is_here, where_is(name), \
    remember_them, set_mode(mode), call_person(name), text_person(name), mute. Repeat tool results almost verbatim. \
    Never describe strangers beyond a count. Never guess identities. Never talk about faces or photos. \
    The wearer is {{user_name}}; people they know: {{known_names}}.
    """
}

struct AgentSessionConfig {
    var idleTimeout: TimeInterval = 8
    var maxDuration: TimeInterval = 90
    var contextInterval: TimeInterval = 2
    var readyTimeout: TimeInterval = 6
}

enum AgentStatus: Equatable {
    case idle, connecting, listening, speaking, thinking
    case ended(reason: String)

    var label: String {
        switch self {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .listening: return "listening"
        case .speaking: return "speaking"
        case .thinking: return "thinking"
        case let .ended(r): return "ended (\(r))"
        }
    }
    var isLive: Bool { switch self { case .connecting, .listening, .speaking, .thinking: return true; default: return false } }
}

struct AgentLine: Identifiable, Equatable {
    enum Role: String { case user, agent, tool, app }
    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
final class AgentSession: ObservableObject, AgentConversationDelegate {
    @Published private(set) var status: AgentStatus = .idle
    @Published private(set) var transcript: [AgentLine] = []
    @Published private(set) var sessionsOpened = 0
    @Published private(set) var refusedWhileStreaming = 0

    let router: AgentToolRouter
    private let speaker: Speaker
    private let cueGate: CueGate
    private weak var audio: AgentAudioControl?
    private let isStreaming: () -> Bool
    private let agentID: () -> String?
    private let apiKey: () -> String?
    private let userName: () -> String
    private let knownNames: () -> [String]
    private let starter: AgentConversationStarter
    private let config: AgentSessionConfig
    private let clock: () -> TimeInterval
    private let log = Logger(subsystem: "familiar", category: "agent")

    private var conversation: AgentConversation?
    private var pendingPhrase: String?
    private var hasAnswered = false
    private var gateWasConsentActive = false
    private var startedAt: TimeInterval = 0
    private var idleTask: Task<Void, Never>?
    private var maxTask: Task<Void, Never>?
    private var contextTask: Task<Void, Never>?
    private var readyTask: Task<Void, Never>?
    private var toolTasks: [Task<Void, Never>] = []

    var isActive: Bool { conversation != nil }
    var isConfigured: Bool { agentID() != nil }

    init(router: AgentToolRouter, speaker: Speaker, cueGate: CueGate, audio: AgentAudioControl?, isStreaming: @escaping () -> Bool,
         agentID: @escaping () -> String? = { Secrets.elevenLabsAgentID }, apiKey: @escaping () -> String? = { Secrets.elevenLabsAPIKey },
         userName: @escaping () -> String, knownNames: @escaping () -> [String],
         starter: @escaping AgentConversationStarter, config: AgentSessionConfig = AgentSessionConfig(),
         clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.router = router; self.speaker = speaker; self.cueGate = cueGate; self.audio = audio; self.isStreaming = isStreaming
        self.agentID = agentID; self.apiKey = apiKey; self.userName = userName; self.knownNames = knownNames
        self.starter = starter; self.config = config; self.clock = clock
    }

    // MARK: Lifecycle

    /// Opens a session for an unparsed wake-word phrase; a second phrase while live is sent as a follow-up turn.
    func open(phrase: String) async {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if let conversation {
            guard !text.isEmpty else { return }
            transcript.append(AgentLine(role: .user, text: text))
            disarmIdle()
            try? await conversation.sendMessage(text)
            return
        }
        if isStreaming() {
            refusedWhileStreaming += 1
            transcript.append(AgentLine(role: .app, text: Phrasebook.notWhileStreaming))
            await say(Phrasebook.notWhileStreaming)
            return
        }
        guard let id = agentID() else {
            transcript.append(AgentLine(role: .app, text: "no agent id configured"))
            await say(Phrasebook.didNotGetThat)
            return
        }
        status = .connecting
        transcript = text.isEmpty ? [] : [AgentLine(role: .user, text: text)]
        pendingPhrase = text.isEmpty ? nil : text
        hasAnswered = false
        gateWasConsentActive = cueGate.consentActive
        cueGate.consentActive = true                       // holds routine cues while the agent has the audio path
        speaker.stopAll()
        audio?.pauseForAgent()
        let request = AgentStartRequest(agentID: id, apiKey: apiKey(), prompt: Phrasebook.agentSystemPrompt,
                                        dynamicVariables: ["user_name": userName(), "known_names": knownNames().joined(separator: ", ")])
        do {
            let c = try await starter(request, self)
            guard conversation == nil else { await c.end(); return }
            conversation = c
            sessionsOpened += 1
            startedAt = clock()
            log.info("agent session opened")
        } catch {
            log.error("agent start failed: \(error.localizedDescription, privacy: .public)")
            transcript.append(AgentLine(role: .app, text: "start failed: \(error.localizedDescription)"))
            restoreAudio()
            status = .ended(reason: "start failed")
            await say(Phrasebook.assistantUnavailable)
            return
        }
        if status == .connecting { status = .listening }
        maxTask = Task { [weak self, config] in
            try? await Task.sleep(for: .seconds(config.maxDuration))
            guard !Task.isCancelled else { return }
            await self?.end(reason: "max duration")
        }
        contextTask = Task { [weak self, config] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.contextInterval))
                guard !Task.isCancelled, let self, let c = self.conversation else { return }
                try? await c.updateContext(self.router.sceneContext())
            }
        }
        readyTask = Task { [weak self, config] in
            try? await Task.sleep(for: .seconds(config.readyTimeout))
            guard !Task.isCancelled else { return }
            await self?.flushPendingPhrase()                // agent never reported ready; send anyway
        }
    }

    /// The wearer said "cancel" or tapped stop.
    func cancel() async { await end(reason: "cancelled") }

    func end(reason: String) async {
        guard let c = conversation else { return }
        conversation = nil
        idleTask?.cancel(); maxTask?.cancel(); contextTask?.cancel(); readyTask?.cancel()
        idleTask = nil; maxTask = nil; contextTask = nil; readyTask = nil
        pendingPhrase = nil
        await c.end()
        restoreAudio()
        status = .ended(reason: reason)
        log.info("agent session ended: \(reason, privacy: .public) after \(self.clock() - self.startedAt, format: .fixed(precision: 1)) s")
    }

    private func restoreAudio() {
        cueGate.consentActive = gateWasConsentActive
        do { try audio?.resumeAfterAgent() } catch { log.error("engine restart failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func say(_ text: String) async {
        await speaker.speak(Utterance(text: text, priority: 0, category: "agent", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
    }

    // MARK: Timers

    private func armIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self, config] in
            try? await Task.sleep(for: .seconds(config.idleTimeout))
            guard !Task.isCancelled else { return }
            await self?.end(reason: "idle")
        }
    }
    private func disarmIdle() { idleTask?.cancel(); idleTask = nil }

    private func flushPendingPhrase() async {
        guard let c = conversation, let p = pendingPhrase else { return }
        pendingPhrase = nil
        readyTask?.cancel(); readyTask = nil
        try? await c.sendMessage(p)
    }

    // MARK: AgentConversationDelegate

    func conversationReady() {
        guard conversation != nil else { return }
        Task { await flushPendingPhrase() }
    }

    func conversationAgentState(_ s: AgentActivity) {
        guard conversation != nil else { return }
        switch s {
        case .speaking: status = .speaking; disarmIdle()
        case .thinking: status = .thinking; disarmIdle()
        case .listening: status = .listening; if hasAnswered { armIdle() }
        }
    }

    func conversationAgentSaid(_ text: String) {
        guard conversation != nil else { return }
        hasAnswered = true
        transcript.append(AgentLine(role: .agent, text: text))
        if status == .listening { armIdle() }
    }

    func conversationUserSaid(_ text: String) {
        guard conversation != nil else { return }
        transcript.append(AgentLine(role: .user, text: text))
        disarmIdle()
    }

    func conversationToolCall(_ call: AgentToolCall) {
        guard conversation != nil else { return }
        disarmIdle()
        status = .thinking
        toolTasks.append(Task { [weak self] in await self?.handle(call) })
    }

    func conversationDisconnected() {
        guard conversation != nil else { return }
        Task { await end(reason: "disconnected") }
    }

    private func handle(_ call: AgentToolCall) async {
        guard let c = conversation else { return }
        let result = await router.handle(call)
        transcript.append(AgentLine(role: .tool, text: "\(call.name) → \(result.text)"))
        try? await c.sendToolResult(id: call.id, result: result.text, isError: result.isError)
        if result.endsSession {
            await end(reason: "tool \(call.name)")
            await result.afterEnd?()
        } else {
            hasAnswered = true
            if status == .thinking { status = .listening }
            armIdle()                                       // the agent re-disarms when it starts speaking
        }
    }
}

// MARK: - Live SDK conversation

#if canImport(ElevenLabs)
/// Wraps `ElevenLabs.Conversation`. Private agents get a conversation token via the API key; public ones start by id.
@MainActor
final class LiveAgentConversation: AgentConversation {
    private let conversation: Conversation
    private init(_ c: Conversation) { conversation = c }

    var isActive: Bool { conversation.state.isActive }
    func sendMessage(_ text: String) async throws { try await conversation.sendMessage(text) }
    func updateContext(_ text: String) async throws { try await conversation.updateContext(text) }
    func sendToolResult(id: String, result: String, isError: Bool) async throws {
        try await conversation.sendToolResult(for: id, result: result, isError: isError)
    }
    func end() async { await conversation.endConversation() }

    static let starter: AgentConversationStarter = { request, delegate in
        var config = ConversationConfig()
        config.agentOverrides = AgentOverrides(prompt: request.prompt)
        config.dynamicVariables = request.dynamicVariables
        config.onAgentReady = { Task { @MainActor in delegate.conversationReady() } }
        config.onAgentResponse = { text, _ in Task { @MainActor in delegate.conversationAgentSaid(text) } }
        config.onUserTranscript = { text, _ in Task { @MainActor in delegate.conversationUserSaid(text) } }
        config.onAgentStateChange = { s in
            let mapped: AgentActivity
            switch s { case .speaking: mapped = .speaking; case .thinking: mapped = .thinking; default: mapped = .listening }
            Task { @MainActor in delegate.conversationAgentState(mapped) }
        }
        config.onDisconnect = { _ in Task { @MainActor in delegate.conversationDisconnected() } }
        config.onUnhandledClientToolCall = { event in
            let params = (try? event.getParameters()) ?? [:]
            let call = AgentToolCall(id: event.toolCallId, name: event.toolName, parameters: params)
            Task { @MainActor in delegate.conversationToolCall(call) }
        }
        let c: Conversation
        if let key = request.apiKey {
            let token = try await fetchConversationToken(agentID: request.agentID, apiKey: key)
            c = try await ElevenLabs.startConversation(conversationToken: token, config: config)
        } else {
            c = try await ElevenLabs.startConversation(agentId: request.agentID, config: config)
        }
        return LiveAgentConversation(c)
    }

    /// `GET /v1/convai/conversation/token?agent_id=…` with `xi-api-key`; only the agent id leaves the phone.
    static func fetchConversationToken(agentID: String, apiKey: String) async throws -> String {
        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/convai/conversation/token")!
        comps.queryItems = [URLQueryItem(name: "agent_id", value: agentID)]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        struct TokenResponse: Decodable { let token: String }
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }
}
#endif

// MARK: - Simulator / test stand-in

/// No network, no audio: answers the opening phrase with one scripted `who_is_here` tool call and echoes the result,
/// so the Simulator shows the full lifecycle (open → tool → answer → idle → end → engine back).
@MainActor
final class SimulatedAgentConversation: AgentConversation {
    private weak var delegate: AgentConversationDelegate?
    private(set) var isActive = true
    private(set) var messages: [String] = []
    private(set) var contexts: [String] = []
    private(set) var toolResults: [(id: String, result: String, isError: Bool)] = []

    init(delegate: AgentConversationDelegate) { self.delegate = delegate }

    static let starter: AgentConversationStarter = { _, delegate in
        let c = SimulatedAgentConversation(delegate: delegate)
        Task { @MainActor in delegate.conversationReady() }
        return c
    }

    func sendMessage(_ text: String) async throws {
        messages.append(text)
        delegate?.conversationAgentState(.thinking)
        let name = Self.toolName(for: text)
        var params: [String: Any] = [:]
        if let n = Self.nameArgument(in: text) { params["name"] = n }
        if name == "set_mode", let m = ["quiet", "normal", "chatty"].first(where: { text.lowercased().contains($0) }) { params["mode"] = m }
        delegate?.conversationToolCall(AgentToolCall(id: "sim-\(messages.count)", name: name, parameters: params))
    }
    func updateContext(_ text: String) async throws { contexts.append(text) }
    func sendToolResult(id: String, result: String, isError: Bool) async throws {
        toolResults.append((id, result, isError))
        guard isActive else { return }
        delegate?.conversationAgentState(.speaking)
        delegate?.conversationAgentSaid(result)
        delegate?.conversationAgentState(.listening)
    }
    func end() async { isActive = false }

    static func toolName(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("remember") { return "remember_them" }
        if t.contains("mute") && !t.contains("unmute") { return "mute" }
        if t.contains("mode") { return "set_mode" }
        if t.contains("call ") { return "call_person" }
        if t.contains("text ") || t.contains("message") { return "text_person" }
        if t.contains("where") { return "where_is" }
        return "who_is_here"
    }
    static func nameArgument(in text: String) -> String? {
        let words = text.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        if let i = words.firstIndex(where: { ["is", "call", "text", "message"].contains($0.lowercased()) }), i + 1 < words.count {
            let n = words[i + 1]
            if !n.isEmpty, n.first!.isUppercase { return n }
        }
        return nil
    }
}
