import Foundation

/// ElevenLabs Scribe for the few seconds where a name is said ("His name is Jagadeep"): on-device recognition
/// turns unusual names into "JD" or "Jugo B". Only that slice of audio is sent, only when a name is being taken.
final class ScribeTranscriber: @unchecked Sendable {
    let apiKey: String?
    let session: URLSession
    var model = "scribe_v1"

    init(apiKey: String? = Secrets.elevenLabsAPIKey, session: URLSession = MetaModelClient.makeSession()) {
        self.apiKey = apiKey; self.session = session
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    func transcribe(wav: Data, timeout: TimeInterval = 4) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw MetaModelClient.ClientError.missingKey }
        let boundary = "poyo-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model_id", model)
        field("tag_audio_events", "false")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw MetaModelClient.ClientError.http(code) }
        struct Reply: Decodable { let text: String }
        return try JSONDecoder().decode(Reply.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-transcribes what was said between `start` and `end` (host clock) from the rolling audio, or nil.
    func retranscribe(_ recorder: AudioChunkClipRecorder?, from start: TimeInterval, to end: TimeInterval) async -> String? {
        guard isConfigured, let recorder else { return nil }
        let (samples, rate) = recorder.slice(from: start - 0.4, to: end + 0.4)
        guard samples.count > Int(rate * 0.3) else { return nil }
        let text = try? await transcribe(wav: WAVWriter.data(samples: samples, sampleRate: rate))
        if let text { DiagnosticLog.write("scribe: \(text)") }
        return text?.isEmpty == false ? text : nil
    }
}
