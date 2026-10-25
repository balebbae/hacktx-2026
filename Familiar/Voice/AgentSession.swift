import Foundation
import QuartzCore
import os
#if canImport(ElevenLabs)
import ElevenLabs
#endif

// S8 — always-on ElevenLabs agent, text only. The conversation is a WebSocket with no audio of its own: it reads the
// on-device transcript and its replies are spoken by our `Speaker` through the one audio engine (Route A: phone mic,
// glasses A2DP). A voice session would open Bluetooth HFP, and HFP ends the glasses camera stream; text keeps both up.

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
    func conversationAgentSaid(_ text: String)
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

extension Phrasebook {
    static let assistantUnavailable = "Assistant unavailable."
    /// App-side prompt override so the demo works even if the dashboard still has the default prompt.
    static let agentSystemPrompt = """
    You help {{user_name}}, a blind person wearing camera glasses. You receive text only and your replies are spoken. \
    Messages starting with [to you] are addressed to you: always answer, in at most 12 words. \
    Messages starting with [overheard] are the wearer talking to someone else: reply exactly SKIP unless the wearer \
    clearly needs something you can give (where someone is, who is here, what is around); then answer in at most 12 words. \
    Context updates say who is visible, what is around and what other people said; never reply to them. \
    Use the client tools for anything about the room: who_is_here, where_is(name), describe_surroundings, remember_them, \
    set_mode(mode), call_person(name), text_person(name), mute. Repeat tool results almost verbatim. \
    Only these people may be named: {{known_names}}. Never name, describe or guess anyone else, even if you heard \
    their name; say someone. Never talk about faces or photos. Never agree to remember anyone yourself: only the \
    remember_them tool can, and the other person must say yes to it. Your name is Poyo, but never say it. \
    Give directions as clock positions (12 o'clock is straight ahead).
    """
}

struct AgentSessionConfig {
    var contextInterval: TimeInterval = 2
    var reconnectDelays: [TimeInterval] = [1, 2, 5, 10]
}

enum AgentStatus: Equatable {
    case idle, connecting, live
    case ended(reason: String)

    var label: String {
        switch self {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .live: return "live"
        case let .ended(r): return "ended (\(r))"
        }
    }
    var isLive: Bool { self == .connecting || self == .live }
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

    let router: AgentToolRouter
    private let speaker: Speaker
    private let cueGate: CueGate
    private let agentID: () -> String?
    private let apiKey: () -> String?
    private let userName: () -> String
    private let knownNames: () -> [String]
    private let starter: AgentConversationStarter
    private let config: AgentSessionConfig
    private let log = Logger(subsystem: "familiar", category: "agent")

    /// True while a consent flow runs: the people in the room talk to each other; the agent neither listens nor speaks.
    var consentActive: () -> Bool = { false }
    /// True while the wake word collects a command: that text reaches `ask` (or a built-in command), never the feed.
    var wakeWordCollecting: () -> Bool = { false }
    /// The rolling transcript, re-sent as context after every (re)connect.
    var recentSpeech: () -> [TranscriptSegment] = { [] }

    private var conversation: AgentConversation?
    private var keeper: Task<Void, Never>?
    private var feed: Task<Void, Never>?
    private var lastContext: String?
    private var awaitingAnswer = false

    var isActive: Bool { conversation != nil }
    var isConfigured: Bool { agentID() != nil }

    init(router: AgentToolRouter, speaker: Speaker, cueGate: CueGate,
         agentID: @escaping () -> String? = { Secrets.elevenLabsAgentID }, apiKey: @escaping () -> String? = { Secrets.elevenLabsAPIKey },
         userName: @escaping () -> String, knownNames: @escaping () -> [String],
         starter: @escaping AgentConversationStarter, config: AgentSessionConfig = AgentSessionConfig()) {
        self.router = router; self.speaker = speaker; self.cueGate = cueGate
        self.agentID = agentID; self.apiKey = apiKey; self.userName = userName; self.knownNames = knownNames
        self.starter = starter; self.config = config
    }

    // MARK: Lifecycle

    /// Opens the conversation and keeps it open for the whole session (reconnecting with backoff), and feeds it every
    /// final transcript segment from `speech`.
    func start(speech: AsyncStream<TranscriptSegment>?) {
        guard keeper == nil, isConfigured else { return }
        keeper = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                var wait = self.config.contextInterval
                if self.conversation == nil {
                    if await self.connect() { attempt = 0 } else {
                        wait = self.config.reconnectDelays[min(attempt, self.config.reconnectDelays.count - 1)]
                        attempt += 1
                    }
                } else {
                    await self.pushContext()
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
        if let speech { feed = Task { [weak self] in for await seg in speech { await self?.hear(seg) } } }
    }

    func stop() async {
        keeper?.cancel(); keeper = nil
        feed?.cancel(); feed = nil
        guard let c = conversation else { return }
        conversation = nil
        await c.end()
        status = .ended(reason: "stopped")
    }

    private func connect() async -> Bool {
        guard let id = agentID() else { return false }
        status = .connecting
        let request = AgentStartRequest(agentID: id, apiKey: apiKey(), prompt: Phrasebook.agentSystemPrompt,
                                        dynamicVariables: ["user_name": userName(), "known_names": knownNames().joined(separator: ", ")])
        do {
            let c = try await starter(request, self)
            guard keeper != nil else { await c.end(); return true }   // stopped while connecting
            conversation = c
            sessionsOpened += 1
            status = .live
            lastContext = nil
            let recent = recentSpeech().filter(\.isFinal).map { "\($0.speaker == .other ? "Other person" : "Wearer"): \($0.text)" }
            if !recent.isEmpty { try? await c.updateContext("Speech so far:\n" + recent.joined(separator: "\n")) }
            await pushContext()
            log.info("agent session opened")
            return true
        } catch {
            log.error("agent start failed: \(error.localizedDescription, privacy: .public)")
            transcript.append(AgentLine(role: .app, text: "connect failed: \(error.localizedDescription)"))
            status = .ended(reason: "connect failed")
            return false
        }
    }

    // MARK: Input

    /// A phrase addressed to the assistant: a "Poyo, …" phrase that is not a built-in command, or a button.
    func ask(_ phrase: String) async {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcript.append(AgentLine(role: .user, text: text))
        guard isConfigured else { await say(Phrasebook.didNotGetThat); return }
        guard let c = conversation else { await say(Phrasebook.assistantUnavailable); return }
        awaitingAnswer = true
        try? await c.sendMessage("[to you] \(text)")
    }

    /// Ongoing speech. The wearer's words are turns the agent may answer (it replies SKIP when it has nothing useful);
    /// other people's words are context only. Nothing is sent while a consent flow runs.
    func hear(_ seg: TranscriptSegment) async {
        guard seg.isFinal, let c = conversation, !consentActive() else { return }
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, WakeWord.find(in: text) == nil, !wakeWordCollecting() else { return }
        if seg.speaker == .other {
            try? await c.updateContext("Other person said: \(text)")
        } else {
            transcript.append(AgentLine(role: .user, text: text))
            try? await c.sendMessage("[overheard] \(text)")
        }
    }

    /// Who is visible and what is around, sent only when it changed.
    private func pushContext() async {
        guard let c = conversation else { return }
        let context = router.sceneContext()
        guard context != lastContext else { return }
        lastContext = context
        try? await c.updateContext(context)
    }

    private func say(_ text: String, priority: Int = 0) async {
        await speaker.speak(Utterance(text: text, priority: priority, category: "agent", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
    }

    /// nil for SKIP; the wake word and descriptions of people never come out of the speaker.
    static func speakable(_ text: String) -> String? { SpeechSanitizer.clean(text, maxWords: 40) }

    // MARK: AgentConversationDelegate

    func conversationAgentSaid(_ text: String) {
        guard conversation != nil else { return }
        let answer = awaitingAnswer
        awaitingAnswer = false
        guard let line = Self.speakable(text) else { return }
        transcript.append(AgentLine(role: .agent, text: line))
        guard !consentActive() else { return }
        // Answers to the wearer interrupt like a command reply; unsolicited remarks queue behind cues and obey mute.
        let u = Utterance(text: line, priority: answer ? 0 : 1, category: "agent", personID: nil, dedupeKey: answer ? nil : "agent", audience: .user, earcon: false)
        guard cueGate.admit(u) else { return }
        Task { await speaker.speak(u) }
    }

    func conversationToolCall(_ call: AgentToolCall) {
        guard let c = conversation else { return }
        Task {
            let result = await router.handle(call)
            transcript.append(AgentLine(role: .tool, text: "\(call.name) → \(result.text)"))
            try? await c.sendToolResult(id: call.id, result: result.text, isError: result.isError)
        }
    }

    func conversationDisconnected() {
        guard conversation != nil else { return }
        conversation = nil
        status = .ended(reason: "disconnected")       // the keeper reconnects
    }
}

// MARK: - Live SDK conversation

#if canImport(ElevenLabs)
/// Wraps `ElevenLabs.Conversation` in text-only mode. Public agents connect by id; private ones through a signed
/// WebSocket URL fetched with the API key (conversation tokens are voice-only).
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
        config.conversationOverrides = ConversationOverrides(textOnly: true)
        config.agentOverrides = AgentOverrides(prompt: request.prompt)
        config.dynamicVariables = request.dynamicVariables
        config.onAgentResponse = { text, _ in Task { @MainActor in delegate.conversationAgentSaid(text) } }
        config.onUnhandledClientToolCall = { event in
            let params = (try? event.getParameters()) ?? [:]
            let call = AgentToolCall(id: event.toolCallId, name: event.toolName, parameters: params)
            Task { @MainActor in delegate.conversationToolCall(call) }
        }
        // `startConversation` overwrites `config.onDisconnect` with this argument, so it must be passed here.
        let disconnected: @Sendable (DisconnectionReason) -> Void = { _ in Task { @MainActor in delegate.conversationDisconnected() } }
        let c: Conversation
        if let key = request.apiKey {
            let url = try await fetchSignedURL(agentID: request.agentID, apiKey: key)
            c = try await ElevenLabs.startConversation(signedWebSocketURL: url, config: config, onDisconnect: disconnected)
        } else {
            c = try await ElevenLabs.startConversation(agentId: request.agentID, config: config, onDisconnect: disconnected)
        }
        return LiveAgentConversation(c)
    }

    /// `GET /v1/convai/conversation/get-signed-url?agent_id=…` with `xi-api-key`; only the agent id leaves the phone.
    static func fetchSignedURL(agentID: String, apiKey: String) async throws -> String {
        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/convai/conversation/get-signed-url")!
        comps.queryItems = [URLQueryItem(name: "agent_id", value: agentID)]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        struct SignedURL: Decodable { let signed_url: String }
        return try JSONDecoder().decode(SignedURL.self, from: data).signed_url
    }
}
#endif

// MARK: - Simulator / test stand-in

/// No network: answers [overheard] turns with SKIP and [to you] turns with one scripted tool call whose result it
/// echoes, so the Simulator shows the whole loop (speech → agent → tool → spoken answer).
@MainActor
final class SimulatedAgentConversation: AgentConversation {
    private weak var delegate: AgentConversationDelegate?
    private(set) var isActive = true
    private(set) var messages: [String] = []
    private(set) var contexts: [String] = []
    private(set) var toolResults: [(id: String, result: String, isError: Bool)] = []

    init(delegate: AgentConversationDelegate) { self.delegate = delegate }

    static let starter: AgentConversationStarter = { _, delegate in SimulatedAgentConversation(delegate: delegate) }

    func sendMessage(_ text: String) async throws {
        messages.append(text)
        guard text.hasPrefix("[to you]") else { delegate?.conversationAgentSaid("SKIP"); return }
        let body = String(text.dropFirst("[to you]".count)).trimmingCharacters(in: .whitespaces)
        var params: [String: Any] = [:]
        if let n = Self.nameArgument(in: body) { params["name"] = n }
        let name = Self.toolName(for: body)
        if name == "set_mode", let m = ["quiet", "normal", "chatty"].first(where: { body.lowercased().contains($0) }) { params["mode"] = m }
        delegate?.conversationToolCall(AgentToolCall(id: "sim-\(messages.count)", name: name, parameters: params))
    }
    func updateContext(_ text: String) async throws { contexts.append(text) }
    func sendToolResult(id: String, result: String, isError: Bool) async throws {
        toolResults.append((id, result, isError))
        if isActive { delegate?.conversationAgentSaid(result) }
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
        if t.contains("around") || t.contains("see") || t.contains("front") { return "describe_surroundings" }
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
