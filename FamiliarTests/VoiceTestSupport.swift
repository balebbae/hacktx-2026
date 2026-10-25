import Foundation
import XCTest
@testable import Familiar

final class ManualClock: @unchecked Sendable {
    var now: TimeInterval
    init(_ now: TimeInterval = 100) { self.now = now }
}

final class FakeSynth: SpeechSynthesizer, @unchecked Sendable {
    struct Failed: Error {}
    let id: String
    var duration: TimeInterval = 0.5
    var failTexts: Set<String> = []
    /// Seconds a text takes to synthesize (real time, cancellable), e.g. an uncached Poyo answer.
    var delays: [String: TimeInterval] = [:]
    private let lock = NSLock()
    private var log: [String] = []
    var texts: [String] { lock.lock(); defer { lock.unlock() }; return log }

    init(id: String = "fake") { self.id = id }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        lock.lock(); log.append(text); lock.unlock()
        if failTexts.contains(text) { throw Failed() }
        if let d = delays[text] { try await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
        return SynthesizedAudio(samples: [Float](repeating: 0.1, count: Int(duration * 16_000)), sampleRate: 16_000, source: id)
    }
}

/// Records what was played. `holdSeconds` keeps each utterance "playing" in real time so queueing can be observed.
final class FakePlayback: PCMPlayback, @unchecked Sendable {
    var holdSeconds: TimeInterval = 0
    let clock: () -> TimeInterval
    private let lock = NSLock()
    private var log: [SynthesizedAudio] = []
    private var stopCount = 0
    private var generation = 0
    var played: [SynthesizedAudio] { lock.lock(); defer { lock.unlock() }; return log }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return stopCount }

    init(clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) { self.clock = clock }

    func play(_ audio: SynthesizedAudio, audience: Audience) async -> ClosedRange<TimeInterval>? {
        let gen: Int = { lock.lock(); defer { lock.unlock() }; log.append(audio); return generation }()
        let start = clock()
        var waited: TimeInterval = 0
        while waited < holdSeconds {
            try? await Task.sleep(nanoseconds: 5_000_000)
            waited += 0.005
            let cut: Bool = { lock.lock(); defer { lock.unlock() }; return generation != gen }()
            if cut { return nil }
        }
        return start...(start + audio.duration)
    }

    func stop() { lock.lock(); stopCount += 1; generation += 1; lock.unlock() }
}

/// Streams fixed chunks; `failStream` makes the stream fail before its first chunk, `cached` texts return nil.
final class FakeStreamingSynth: SpeechSynthesizer, StreamingSpeechSynthesizer, @unchecked Sendable {
    let id = "stream"
    var chunks: [[Float]] = [[Float](repeating: 0.2, count: 1_600), [Float](repeating: 0.3, count: 1_600), [Float](repeating: 0.1, count: 800)]
    var failStream = false
    var cached: Set<String> = []
    var streamSampleRate: Double { 16_000 }
    private let lock = NSLock()
    private var streamedLog: [String] = []
    private var synthesizedLog: [String] = []
    var streamed: [String] { lock.withLock { streamedLog } }
    var synthesized: [String] { lock.withLock { synthesizedLog } }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        lock.withLock { synthesizedLog.append(text) }
        return SynthesizedAudio(samples: [Float](repeating: 0.1, count: 8_000), sampleRate: 16_000, source: id)
    }

    func stream(_ text: String) -> AsyncThrowingStream<[Float], Error>? {
        guard !cached.contains(text) else { return nil }
        lock.withLock { streamedLog.append(text) }
        let chunks = self.chunks, fail = failStream
        return AsyncThrowingStream { cont in
            if fail { cont.finish(throwing: ElevenLabsTTS.Failure.timeout); return }
            for c in chunks { cont.yield(c) }
            cont.finish()
        }
    }
}

/// Records streamed playbacks (prefix, chunks in order, gain) next to the plain ones.
final class FakeStreamingPlayback: PCMPlayback, StreamingPCMPlayback, @unchecked Sendable {
    struct Streamed { let prefix: [Float]; let chunks: [[Float]]; let gain: Float }
    private let lock = NSLock()
    private var plain: [SynthesizedAudio] = []
    private var streamedLog: [Streamed] = []
    var played: [SynthesizedAudio] { lock.withLock { plain } }
    var streams: [Streamed] { lock.withLock { streamedLog } }

    func play(_ audio: SynthesizedAudio, audience: Audience) async -> ClosedRange<TimeInterval>? {
        lock.withLock { plain.append(audio) }
        let start = CACurrentMediaTime()
        return start...(start + audio.duration)
    }

    func playStream(_ chunks: AsyncThrowingStream<[Float], Error>, sampleRate: Double, prefix: [Float], gain: Float, audience: Audience) async -> ClosedRange<TimeInterval>? {
        let start = CACurrentMediaTime()
        var got: [[Float]] = []
        do { for try await c in chunks { got.append(c) } } catch {}
        let streamed = Streamed(prefix: prefix, chunks: got, gain: gain)
        lock.withLock { streamedLog.append(streamed) }
        let samples = prefix.count + got.reduce(0) { $0 + $1.count }
        return samples > 0 ? start...(start + Double(samples) / sampleRate) : nil
    }

    func stop() {}
}

final class FailingTranscriber: Transcriber {
    let error: Error
    init(error: Error = TranscriberError.unavailable("test")) { self.error = error }
    func subscribe() -> AsyncStream<TranscriptSegment> { AsyncStream { $0.finish() } }
    func start(audio: AudioInput) async throws { throw error }
    func stop() {}
    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] { [] }
}

final class TTSStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data)] = []
    static let lock = NSLock()

    static func reset() { lock.lock(); handler = nil; delay = 0; requests = []; lock.unlock() }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TTSStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = TTSStubURLProtocol.readBody(request)
        TTSStubURLProtocol.lock.lock()
        TTSStubURLProtocol.requests.append((request, body))
        let handler = TTSStubURLProtocol.handler
        let delay = TTSStubURLProtocol.delay
        TTSStubURLProtocol.lock.unlock()
        let work = { [self] in
            do {
                let (status, data) = try handler?(request) ?? (200, Data())
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work) } else { work() }
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: bufferSize)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

enum TestTracks {
    static func known(_ name: String, id: UUID, track: Int = 1, band: BearingBand = .ahead, distance: Distance = .close, now: TimeInterval = 0) -> TrackSnapshot {
        ScriptedPerception.makeSnapshot(trackID: track, identity: .known(personID: id, name: name, score: 0.9), band: band, distance: distance, now: now)
    }
    static func unknown(track: Int, band: BearingBand = .ahead, distance: Distance = .medium, now: TimeInterval = 0) -> TrackSnapshot {
        ScriptedPerception.makeSnapshot(trackID: track, identity: .unknown(bestScore: 0.2), band: band, distance: distance, now: now)
    }
}

extension Utterance {
    static func test(_ text: String, priority: Int = 1, dedupeKey: String? = nil, earcon: Bool = false) -> Utterance {
        Utterance(text: text, priority: priority, category: "test", personID: nil, dedupeKey: dedupeKey, audience: .user, earcon: earcon)
    }
}
