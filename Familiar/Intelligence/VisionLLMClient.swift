import Foundation

/// A multimodal chat model: system prompt + earlier turns + text + an optional JPEG → JSON matching `schema`.
/// The JPEG is always a `FrameRedactor` output (every face blacked out on the phone). `history` is what the wearer
/// and Poyo said lately (`DialogueMemory.messages`), as "user" / "assistant" turns before the final user message.
protocol VisionLLM: AnyObject {
    var isConfigured: Bool { get }
    func complete(system: String, history: [(role: String, text: String)], text: String, imageJPEG: Data?, schemaName: String, schema: [String: Any], maxTokens: Int, cacheKey: String, timeout: TimeInterval) async throws -> [String: Any]
}

extension VisionLLM {
    func complete(system: String, text: String, imageJPEG: Data?, schemaName: String, schema: [String: Any], maxTokens: Int, cacheKey: String, timeout: TimeInterval) async throws -> [String: Any] {
        try await complete(system: system, history: [], text: text, imageJPEG: imageJPEG, schemaName: schemaName, schema: schema, maxTokens: maxTokens, cacheKey: cacheKey, timeout: timeout)
    }
}

/// OpenAI-compatible `/chat/completions` with `image_url` data URIs. Defaults to the Meta Model API
/// (`muse-spark-1.3`, the key already in Secrets); `VISION_API_URL` / `VISION_API_KEY` / `VISION_MODEL` point it at
/// any other compatible endpoint (e.g. Gemini's OpenAI-compatible URL).
final class VisionLLMClient: VisionLLM, @unchecked Sendable {
    let endpoint: URL
    let apiKey: String?
    let model: String
    let session: URLSession
    private(set) var lastLatency: TimeInterval?

    init(endpoint: URL = Secrets.visionAPIURL ?? MetaModelClient.endpoint,
         apiKey: String? = Secrets.visionAPIKey ?? Secrets.metaModelAPIKey,
         model: String = Secrets.visionModel ?? MetaModelClient.model,
         session: URLSession = MetaModelClient.sharedSession) {
        self.endpoint = endpoint; self.apiKey = apiKey; self.model = model; self.session = session
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func body(model: String, system: String, history: [(role: String, text: String)] = [], text: String, imageJPEG: Data?, schemaName: String, schema: [String: Any], maxTokens: Int, cacheKey: String) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        if let imageJPEG {
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + imageJPEG.base64EncodedString()]])
        }
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { ["role": $0.role, "content": $0.text] }
        messages.append(["role": "user", "content": content])
        var body: [String: Any] = [
            "model": model,
            "max_completion_tokens": maxTokens,
            "messages": messages,
            "response_format": ["type": "json_schema", "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
        ]
        if model.hasPrefix("muse") {
            // Measured: `minimal` answers in 1.6–2.4 s; `low` sometimes runs out of tokens while reasoning.
            body["reasoning_effort"] = "minimal"
            body["prompt_cache_key"] = cacheKey
        }
        return body
    }

    func complete(system: String, history: [(role: String, text: String)], text: String, imageJPEG: Data?, schemaName: String, schema: [String: Any], maxTokens: Int, cacheKey: String, timeout: TimeInterval) async throws -> [String: Any] {
        guard let apiKey, !apiKey.isEmpty else { throw MetaModelClient.ClientError.missingKey }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(model: model, system: system, history: history, text: text, imageJPEG: imageJPEG, schemaName: schemaName, schema: schema, maxTokens: maxTokens, cacheKey: cacheKey))
        let started = Date()
        let (data, response) = try await session.data(for: request)
        lastLatency = Date().timeIntervalSince(started)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw MetaModelClient.ClientError.http(code) }
        let completion = try MetaModelClient.parse(data)
        guard let obj = MetaModelClient.json(completion.content) else { throw MetaModelClient.ClientError.malformed }
        return obj
    }
}
