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
    private let lock = NSLock()
    private var log: [String] = []
    var texts: [String] { lock.lock(); defer { lock.unlock() }; return log }

    init(id: String = "fake") { self.id = id }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        lock.lock(); log.append(text); lock.unlock()
        if failTexts.contains(text) { throw Failed() }
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
