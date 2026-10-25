import Foundation
import os

/// ElevenLabs text-to-speech. Text only leaves the phone. Cache hit → no network. Miss → fetch, cache, return.
/// Throws (so `FallbackSynthesizer` goes to Apple) when no first byte arrives within `firstByteTimeout`, on any
/// non-2xx status, or on empty audio. At most `maxConcurrent` requests are in flight, and prewarming never gets
/// in the way of a live line: `warm` holds one slot at most and waits while any live request is pending.
final class ElevenLabsTTS: SpeechSynthesizer, StreamingSpeechSynthesizer, @unchecked Sendable {
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
    private let warmSemaphore = AsyncSemaphore(count: 1)
    /// Live requests waiting or in flight; prewarm pauses while this is above zero.
    private let livePending = OSAllocatedUnfairLock(initialState: 0)

    init(apiKey: String, voiceID: String = VoiceFactory.defaultVoiceID, model: String = VoiceFactory.model, cache: PhraseCache = PhraseCache(), session: URLSession = .shared, maxConcurrent: Int = 2) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.model = model
        self.cache = cache
        self.session = session
        self.semaphore = AsyncSemaphore(count: maxConcurrent)
    }

    static func request(apiKey: String, voiceID: String, model: String, text: String, previousText: String, speed: Double = 1.0, stream: Bool = false) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)\(stream ? "/stream" : "")?output_format=pcm_16000")!)
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
        livePending.withLock { $0 += 1 }
        defer { livePending.withLock { $0 -= 1 } }
        let data = try await fetch(text)
        cache.store(data, voiceID: voiceID, model: cacheModel, text: text)
        return SynthesizedAudio(samples: PCM16.decode(data), sampleRate: ElevenLabsTTS.sampleRate, source: id)
    }

    /// Synthesizes into the cache without returning audio; used by `prewarm`. One at a time, and only while no
    /// live line is waiting: a cold cache at boot must not queue an answer behind eighty alert phrases.
    func warm(_ text: String) async throws {
        guard !isCached(text) else { return }
        await warmSemaphore.wait()
        defer { Task { await warmSemaphore.signal() } }
        while livePending.withLock({ $0 }) > 0 { try await Task.sleep(nanoseconds: 50_000_000) }
        guard !isCached(text) else { return }
        let cacheModel = self.cacheModel
        let data = try await fetch(text)
        cache.store(data, voiceID: voiceID, model: cacheModel, text: text)
    }

    private func fetch(_ text: String) async throws -> Data {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }
        let bytes = try await open(text, stream: false)
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        guard data.count >= 2 else { throw Failure.emptyAudio }
        return data
    }

    /// Sends the request and returns the body once the response headers are in. Only the first byte races the
    /// timer; the body streams in afterwards untimed.
    private func open(_ text: String, stream: Bool) async throws -> URLSession.AsyncBytes {
        let req = ElevenLabsTTS.request(apiKey: apiKey, voiceID: voiceID, model: model, text: text, previousText: previousText, speed: speed, stream: stream)
        let timeout = firstByteTimeout
        let session = self.session
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
        return bytes
    }

    // MARK: Streaming

    /// Bytes per emitted chunk: 200 ms of 16 kHz 16-bit audio.
    var streamChunkBytes = 6_400
    var streamSampleRate: Double { ElevenLabsTTS.sampleRate }

    /// `POST …/stream`: 16 kHz samples as the body arrives, so playback starts a few hundred milliseconds after the
    /// request instead of after the whole clip. nil when the text is cached (the plain path is instant then).
    /// Throws before the first chunk on a timeout, a bad status or empty audio, so the caller can fall back; the
    /// whole clip is cached once the stream completes.
    func stream(_ text: String) -> AsyncThrowingStream<[Float], Error>? {
        guard !isCached(text) else { return nil }
        let chunkBytes = streamChunkBytes
        return AsyncThrowingStream { continuation in
            let task = Task { [self] in
                livePending.withLock { $0 += 1 }
                defer { livePending.withLock { $0 -= 1 } }
                await semaphore.wait()
                defer { Task { await semaphore.signal() } }
                do {
                    let bytes = try await open(text, stream: true)
                    var all = Data()
                    var pending = Data()
                    var emitted = false
                    for try await byte in bytes {
                        pending.append(byte)
                        if pending.count >= chunkBytes {
                            all.append(pending)
                            continuation.yield(PCM16.decode(pending))
                            pending.removeAll(keepingCapacity: true)
                            emitted = true
                        }
                    }
                    if pending.count >= 2 {
                        all.append(pending)
                        continuation.yield(PCM16.decode(pending))
                        emitted = true
                    }
                    guard emitted else { throw Failure.emptyAudio }
                    cache.store(all, voiceID: voiceID, model: cacheModel, text: text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
