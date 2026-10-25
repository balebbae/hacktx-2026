import Foundation
import CryptoKit
import UIKit

/// Thin client for the Meta Model API (`muse-spark-1.3`, never the `-contributor` tier). Text only leaves the phone.
/// One shared `URLSession`; strict JSON-schema responses; one retry honouring `Retry-After` on 429 / 503.
final class MetaModelClient: @unchecked Sendable {
    enum ClientError: LocalizedError, Equatable {
        case missingKey
        case http(Int)
        case notStopped(String)
        case malformed
        var errorDescription: String? {
            switch self {
            case .missingKey: return "META_MODEL_API_KEY is not configured."
            case let .http(code): return "Meta Model API returned HTTP \(code)."
            case let .notStopped(reason): return "Meta Model API did not finish (finish_reason=\(reason))."
            case .malformed: return "Meta Model API returned an unexpected payload."
            }
        }
    }

    static let endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    static let model = "muse-spark-1.3"

    let apiKey: String?
    let session: URLSession
    let safetyIdentifier: String
    private(set) var lastRawResponse: String?

    init(apiKey: String?, session: URLSession = MetaModelClient.makeSession(), safetyIdentifier: String = MetaModelClient.defaultSafetyIdentifier()) {
        self.apiKey = apiKey
        self.session = session
        self.safetyIdentifier = safetyIdentifier
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }

    static func defaultSafetyIdentifier() -> String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "simulator"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Prompts

    static let nameSystemPrompt = "You help a blind user remember people they meet. You read a short transcript between USER (the blind wearer) and OTHER (the person they are talking to). Return the first name OTHER gave for themselves, or null if OTHER never introduced themselves. Never return USER's name or a name USER used for someone else. Keep confidence low when unsure."
    static let yesNoSystemPrompt = "You help a blind user remember people they meet. The user just asked someone for permission to remember their face. Classify the reply as yes, no, or unclear. Only a clear agreement is yes."
    static let intentSystemPrompt = "You help a blind user control an assistant. Map the sentence to one intent and an optional person name."
    static let intents = ["whoIsHere", "rememberThem", "quietMode", "normalMode", "chattyMode", "mute", "unmute", "call", "text", "whereIs", "cancel", "repeatLast", "none"]

    static func formatTranscript(_ segments: [TranscriptSegment], maxCharacters: Int = 6000) -> String {
        var lines: [String] = []
        for s in segments where s.isFinal || true {
            let who = s.speaker == .user ? "USER" : "OTHER"
            lines.append("\(who): \(s.text)")
        }
        var text = lines.joined(separator: "\n")
        while text.count > maxCharacters, !lines.isEmpty { lines.removeFirst(); text = lines.joined(separator: "\n") }
        return text
    }

    // MARK: Requests

    struct Completion: Equatable { let content: String; let finishReason: String }

    func introducedName(transcript: String, timeout: TimeInterval = 15) async throws -> NameGuess {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
                                     "properties": ["name": ["type": ["string", "null"]], "confidence": ["type": "number", "minimum": 0, "maximum": 1]],
                                     "required": ["name", "confidence"]]
        let completion = try await complete(system: Self.nameSystemPrompt, user: transcript, schemaName: "IntroducedName", schema: schema, reasoning: "low", maxTokens: 400, cacheKey: "familiar-name-v1", timeout: timeout)
        guard let obj = Self.json(completion.content) else { throw ClientError.malformed }
        var name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if name?.isEmpty == true || name?.lowercased() == "null" { name = nil }
        let confidence = (obj["confidence"] as? Double) ?? (obj["confidence"] as? Int).map(Double.init) ?? 0
        return NameGuess(name: name, confidence: name == nil ? 0 : min(1, max(0, confidence)), source: "meta")
    }

    func yesNo(reply: String, timeout: TimeInterval = 4) async throws -> YesNo {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
                                     "properties": ["answer": ["type": "string", "enum": ["yes", "no", "unclear"]]],
                                     "required": ["answer"]]
        let completion = try await complete(system: Self.yesNoSystemPrompt, user: "REPLY: \(reply)", schemaName: "YesNo", schema: schema, reasoning: "minimal", maxTokens: 300, cacheKey: "familiar-yesno-v1", timeout: timeout)
        guard let obj = Self.json(completion.content), let answer = obj["answer"] as? String else { throw ClientError.malformed }
        switch answer { case "yes": return .yes; case "no": return .no; default: return .unclear }
    }

    struct Intent: Equatable { let intent: String; let name: String? }

    func intent(sentence: String, timeout: TimeInterval = 4) async throws -> Intent {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
                                     "properties": ["intent": ["type": "string", "enum": Self.intents], "name": ["type": ["string", "null"]]],
                                     "required": ["intent", "name"]]
        let completion = try await complete(system: Self.intentSystemPrompt, user: sentence, schemaName: "Intent", schema: schema, reasoning: "minimal", maxTokens: 300, cacheKey: "familiar-intent-v1", timeout: timeout)
        guard let obj = Self.json(completion.content), let intent = obj["intent"] as? String else { throw ClientError.malformed }
        let name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Intent(intent: intent, name: name)
    }

    /// Cheap request issued at launch so the first real call does not pay for TLS + cache warm-up.
    func warmUp() async {
        _ = try? await yesNo(reply: "yes", timeout: 6)
    }

    // MARK: Core

    func complete(system: String, user: String, schemaName: String, schema: [String: Any], reasoning: String, maxTokens: Int, cacheKey: String, timeout: TimeInterval) async throws -> Completion {
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.missingKey }
        let body: [String: Any] = [
            "model": Self.model,
            "reasoning_effort": reasoning,
            "max_completion_tokens": maxTokens,
            "prompt_cache_key": cacheKey,
            "safety_identifier": safetyIdentifier,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "response_format": ["type": "json_schema", "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            lastRawResponse = String(data: data, encoding: .utf8)
            if (code == 429 || code == 503), attempt == 1 {
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
                try await Task.sleep(nanoseconds: UInt64(min(retryAfter, 5) * 1_000_000_000))
                continue
            }
            guard (200..<300).contains(code) else { throw ClientError.http(code) }
            return try Self.parse(data)
        }
    }

    static func parse(_ data: Data) throws -> Completion {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else { throw ClientError.malformed }
        let finish = (first["finish_reason"] as? String) ?? "unknown"
        guard finish == "stop" else { throw ClientError.notStopped(finish) }
        guard let content = message["content"] as? String else { throw ClientError.malformed }
        return Completion(content: content, finishReason: finish)
    }

    static func json(_ content: String) -> [String: Any]? {
        guard let data = content.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// `NameExtractor` on the Meta Model API. Returns an empty guess on any failure so the race continues.
struct MetaNameExtractor: NameExtractor {
    let client: MetaModelClient
    var timeout: TimeInterval = 15
    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess {
        guard client.isConfigured else { return NameGuess(name: nil, confidence: 0, source: "meta") }
        let transcript = MetaModelClient.formatTranscript(segments)
        guard !transcript.isEmpty else { return NameGuess(name: nil, confidence: 0, source: "meta") }
        let guess = (try? await client.introducedName(transcript: "USER's name is \(userName).\n\(transcript)", timeout: timeout)) ?? NameGuess(name: nil, confidence: 0, source: "meta")
        if guess.name?.lowercased() == userName.lowercased() { return NameGuess(name: nil, confidence: 0, source: "meta") }
        return guess
    }
}

struct MetaYesNoClassifier: YesNoClassifier {
    let client: MetaModelClient
    var timeout: TimeInterval = 4
    func classify(_ reply: String) async -> YesNo {
        guard client.isConfigured else { return .unclear }
        return (try? await client.yesNo(reply: reply, timeout: timeout)) ?? .unclear
    }
}
