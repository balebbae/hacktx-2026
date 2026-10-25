import Foundation
import AVFoundation
import QuartzCore

// Types added by S3 for the speech module (Core is frozen).

/// In-progress (not yet final) recognizer text; the wake word watches this for low latency.
struct VolatileText: Equatable { let text: String; let t: TimeInterval }

protocol VolatileTextSource: AnyObject { func subscribeVolatile() -> AsyncStream<VolatileText> }

/// Host-clock moments at which speech stopped (the recognizer's voice-activity verdict). The wake word flushes a
/// request on it instead of waiting for the text to settle; the final result arrives a second or more later.
protocol EndpointSource: AnyObject { func subscribeEndpoints() -> AsyncStream<TimeInterval> }

/// Signals derived from the transcript that are not commands.
enum SpeechSignal: Equatable { case goodbyeDetected(t: TimeInterval) }

/// What the wake word collected after "Poyo", parsed or not (nil command → router says "Sorry, I didn't get that.").
struct WakeWordHit: Equatable { let text: String; let command: Command?; let t: TimeInterval }

enum TranscriberError: Error, Equatable { case unavailable(String), notAuthorized }

/// Rolling transcript window (90 s) shared by the real transcribers.
final class TranscriptWindow: @unchecked Sendable {
    var seconds: TimeInterval
    private var segments: [TranscriptSegment] = []
    private let lock = NSLock()

    init(seconds: TimeInterval = 90) { self.seconds = seconds }

    func append(_ seg: TranscriptSegment) {
        lock.lock(); defer { lock.unlock() }
        segments.append(seg)
        let cutoff = seg.end - seconds
        segments.removeAll { $0.end < cutoff }
    }

    func recent(seconds wanted: TimeInterval, now: TimeInterval) -> [TranscriptSegment] {
        lock.lock(); defer { lock.unlock() }
        let cutoff = now - min(wanted, seconds)
        return segments.filter { $0.end >= cutoff }
    }

    var all: [TranscriptSegment] { lock.lock(); defer { lock.unlock() }; return segments }
}

/// Tries each candidate's `start` in order and forwards the first one that succeeds. Lets the app boot on iOS 18,
/// in the Simulator and on a device without speech assets with the same wiring.
final class FallbackTranscriber: Transcriber, VolatileTextSource, EndpointSource, @unchecked Sendable {
    let candidates: [Transcriber]
    private(set) var active: Transcriber?
    private(set) var startErrors: [String] = []
    private let bus = EventBus<TranscriptSegment>()
    private let volatileBus = EventBus<VolatileText>()
    private let endpointBus = EventBus<TimeInterval>()
    private var forwarders: [Task<Void, Never>] = []

    init(candidates: [Transcriber]) { self.candidates = candidates }

    var activeName: String { active.map { String(describing: type(of: $0)) } ?? "none" }

    func subscribe() -> AsyncStream<TranscriptSegment> { bus.subscribe() }
    func subscribeVolatile() -> AsyncStream<VolatileText> { volatileBus.subscribe() }
    func subscribeEndpoints() -> AsyncStream<TimeInterval> { endpointBus.subscribe() }

    func start(audio: AudioInput) async throws {
        guard active == nil else { return }
        var lastError: Error = TranscriberError.unavailable("no transcriber candidates")
        for candidate in candidates {
            let segs = candidate.subscribe()
            let vol = (candidate as? VolatileTextSource)?.subscribeVolatile()
            let ends = (candidate as? EndpointSource)?.subscribeEndpoints()
            do {
                try await candidate.start(audio: audio)
                active = candidate
                forwarders.append(Task { [bus] in for await s in segs { bus.publish(s) } })
                if let vol { forwarders.append(Task { [volatileBus] in for await v in vol { volatileBus.publish(v) } }) }
                if let ends { forwarders.append(Task { [endpointBus] in for await t in ends { endpointBus.publish(t) } }) }
                return
            } catch {
                lastError = error
                startErrors.append("\(type(of: candidate)): \(error)")
            }
        }
        throw lastError
    }

    func stop() {
        active?.stop()
        active = nil
        forwarders.forEach { $0.cancel() }
        forwarders.removeAll()
    }

    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] { active?.recentSegments(seconds: seconds) ?? [] }
}

/// Builds `AVAudioPCMBuffer`s from 16 kHz Float chunks, converting when a recognizer wants another format.
enum AudioBuffers {
    static let chunkFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    static func buffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buf.frameLength = AVAudioFrameCount(samples.count)
        return buf
    }

    /// Chunk → buffer in `format` (identity when the formats already match). A mismatch would yield silence, not an error.
    static func buffer(for chunk: AudioChunk, in format: AVAudioFormat, converter: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let src = buffer(samples: chunk.samples, sampleRate: chunk.sampleRate) else { return nil }
        if format.sampleRate == src.format.sampleRate && format.channelCount == 1 && format.commonFormat == .pcmFormatFloat32 { return src }
        if converter == nil || converter?.inputFormat != src.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: src.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(src.frameLength) * format.sampleRate / src.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return src
        }
        return error == nil ? out : nil
    }
}

enum SpeechFactory {
    /// SpeechAnalyzer (iOS 26) → SFSpeechRecognizer on-device → silent, whichever starts first.
    /// `speakerGuess` labels final segments (`LoudnessSplit.guess(at:)`); `speechDetected` feeds the VAD from `SpeechDetector`.
    static func makeTranscriber(speakerGuess: ((TimeInterval) -> SpeakerGuess)? = nil, speechDetected: ((Bool, TimeInterval) -> Void)? = nil, promptForAuthorization: Bool = true) -> FallbackTranscriber {
        var candidates: [Transcriber] = []
        if #available(iOS 26, *) {
            let analyzer = SpeechAnalyzerTranscriber()
            analyzer.speakerGuess = speakerGuess
            analyzer.onSpeechDetected = speechDetected
            candidates.append(analyzer)
        }
        let sf = SFSpeechTranscriber()
        sf.speakerGuess = speakerGuess
        sf.promptsForAuthorization = promptForAuthorization
        candidates.append(sf)
        candidates.append(FakeTranscriber(text: ""))
        return FallbackTranscriber(candidates: candidates)
    }

    static func makeCommandSource(transcriber: Transcriber) -> WakeWordCommandSource {
        let source = WakeWordCommandSource()
        source.attach(transcriber)
        return source
    }

    static func makeGoodbyeDetector(transcriber: Transcriber) -> GoodbyeDetector {
        let detector = GoodbyeDetector()
        detector.attach(transcriber)
        return detector
    }
}
