import Foundation

/// ElevenLabs text-to-speech. Text only leaves the phone. Cache hit → no network. Miss → fetch, cache, return.
/// Throws (so `FallbackSynthesizer` goes to Apple) when no first byte arrives within `firstByteTimeout`, on any
/// non-2xx status, or on empty audio. At most `maxConcurrent` requests are in flight.
final class ElevenLabsTTS: SpeechSynthesizer, @unchecked Sendable {
    enum Failure: Error, Equatable { case timeout, httpStatus(Int), emptyAudio, cancelled }

    let id = "elevenlabs"
    let apiKey: String
    let voiceID: String
    let model: String
    let cache: PhraseCache
    let session: URLSession
    /// v4 turbo answers in about 1 s; a tighter limit would fall back to the Apple voice most of the time.
    var firstByteTimeout: TimeInterval = 3
    var previousText = "Here is what I see."
    /// The wearer's speech-rate preference, read per request and clamped to the `speed` range ElevenLabs accepts
    /// (0.7…1.2). `VoiceFactory` wires it to `SpeechPreferences`; the default is the unchanged 1.0.
    var speedProvider: () -> Double = { 1 }
    static let sampleRate: Double = 16_000
    private let semaphore: AsyncSemaphore

    init(apiKey: String, voiceID: String = VoiceFactory.defaultVoiceID, model: String = VoiceFactory.model, cache: PhraseCache = PhraseCache(), session: URLSession = .shared, maxConcurrent: Int = 2) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.model = model
        self.cache = cache
        self.session = session
        self.semaphore = AsyncSemaphore(count: maxConcurrent)
    }

    static func request(apiKey: String, voiceID: String, model: String, text: String, previousText: String, speed: Double = 1.0) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=pcm_16000")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/pcm", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": model,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "speed": speed],
            "previous_text": previousText,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    /// The speed the next request asks for, inside ElevenLabs' accepted range.
    var speed: Double { min(1.2, max(0.7, speedProvider())) }

    /// Pace is rendered into the audio, so a phrase at another speed is another cache entry. 1.0 keeps the plain
    /// model key, so a cache prewarmed before this setting existed stays valid.
    static func cacheModel(_ model: String, speed: Double) -> String {
        speed == 1 ? model : "\(model)@\(String(format: "%.2f", speed))"
    }

    private var cacheModel: String { ElevenLabsTTS.cacheModel(model, speed: speed) }

    func isCached(_ text: String) -> Bool { cache.has(voiceID: voiceID, model: cacheModel, text: text) }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        let cacheModel = self.cacheModel
        if let cached = cache.samples(voiceID: voiceID, model: cacheModel, text: text) {
            return SynthesizedAudio(samples: cached, sampleRate: ElevenLabsTTS.sampleRate, source: "elevenlabs-cache")
        }
        let data = try await fetch(text)
        cache.store(data, voiceID: voiceID, model: cacheModel, text: text)
        return SynthesizedAudio(samples: PCM16.decode(data), sampleRate: ElevenLabsTTS.sampleRate, source: id)
    }

    /// Synthesizes into the cache without returning audio; used by `prewarm`.
    func warm(_ text: String) async throws {
        guard !isCached(text) else { return }
        let cacheModel = self.cacheModel
        let data = try await fetch(text)
        cache.store(data, voiceID: voiceID, model: cacheModel, text: text)
    }

    private func fetch(_ text: String) async throws -> Data {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }
        let req = ElevenLabsTTS.request(apiKey: apiKey, voiceID: voiceID, model: model, text: text, previousText: previousText, speed: speed)
        let timeout = firstByteTimeout
        let session = self.session
        // Race only the response headers (first byte) against the timer; the body streams in afterwards untimed.
        let (bytes, response) = try await withThrowingTaskGroup(of: (URLSession.AsyncBytes, URLResponse).self) { group in
            group.addTask { try await session.bytes(for: req) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw Failure.timeout
            }
            guard let result = try await group.next() else { throw Failure.cancelled }
            group.cancelAll()
            return result
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.httpStatus(http.statusCode) }
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        guard data.count >= 2 else { throw Failure.emptyAudio }
        return data
    }
}
