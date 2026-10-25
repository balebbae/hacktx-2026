import Foundation
import AVFoundation
import CoreMedia
import Speech

/// iOS 26 on-device transcriber built on `SpeechAnalyzer` + `SpeechTranscriber` (+ `SpeechDetector` for VAD).
/// Not available in the Simulator: `start` throws `TranscriberError.unavailable` and `FallbackTranscriber` moves on.
@available(iOS 26, *)
final class SpeechAnalyzerTranscriber: Transcriber, VolatileTextSource, @unchecked Sendable {
    var speakerGuess: ((TimeInterval) -> SpeakerGuess)?
    var onSpeechDetected: ((Bool, TimeInterval) -> Void)?
    /// Asset download progress for the UI (nil when assets are already installed).
    var onAssetProgress: ((Progress) -> Void)?
    private(set) var volatileText = ""
    private(set) var locale: Locale?

    private let window = TranscriptWindow()
    private let bus = EventBus<TranscriptSegment>()
    private let volatileBus = EventBus<VolatileText>()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var baseHostTime: TimeInterval?
    /// Bumped by every `start`/`stop` so a dying analyzer only restarts itself if nobody replaced it.
    private var generation = 0
    private var audio: AudioInput?
    private var recoveries = 0
    static let maxRecoveries = 5

    init() {}

    func subscribe() -> AsyncStream<TranscriptSegment> { bus.subscribe() }
    func subscribeVolatile() -> AsyncStream<VolatileText> { volatileBus.subscribe() }
    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] { window.recent(seconds: seconds, now: CACurrentMediaTime()) }

    func start(audio: AudioInput) async throws {
        guard analyzer == nil else { return }
        generation += 1
        let gen = generation
        self.audio = audio
        guard SpeechTranscriber.isAvailable else { throw TranscriberError.unavailable("SpeechTranscriber is not available on this device") }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? Locale(identifier: "en-US")
        self.locale = locale
        var preset = SpeechTranscriber.Preset.timeIndexedProgressiveTranscription
        preset.attributeOptions.insert(.transcriptionConfidence)
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: preset.transcriptionOptions, reportingOptions: preset.reportingOptions, attributeOptions: preset.attributeOptions)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onAssetProgress?(request.progress)
            try await request.downloadAndInstall()
        }
        // `reportResults: true` so the detector's verdicts can feed `LoudnessSplit`; the prompt's `false` would hide them.
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
        let analyzer = SpeechAnalyzer(modules: [detector, transcriber])
        self.analyzer = analyzer
        let context = AnalysisContext()
        context.contextualStrings[.general] = WakeWord.contextualStrings
        try? await analyzer.setContext(context)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: AudioBuffers.chunkFormat) ?? AudioBuffers.chunkFormat
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        try await analyzer.start(inputSequence: stream)

        let chunks = audio.subscribe()
        tasks.append(Task.detached { [weak self] in
            var converter: AVAudioConverter?
            // Timeline = frames fed so far. Host-clock chunk stamps jitter against the resampler's frame counts, and
            // SpeechAnalyzer kills the session on the first overlap ("Audio input timestamp overlaps…", "RecogRejected").
            var framesFed: AVAudioFramePosition = 0
            for await chunk in chunks {
                guard let self else { return }
                if self.baseHostTime == nil { self.baseHostTime = chunk.timestamp }
                guard let buffer = AudioBuffers.buffer(for: chunk, in: format, converter: &converter), buffer.frameLength > 0 else { continue }
                let start = CMTime(value: framesFed, timescale: CMTimeScale(format.sampleRate))
                framesFed += AVAudioFramePosition(buffer.frameLength)
                continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: start))
            }
        })
        tasks.append(Task.detached { [weak self] in
            do {
                for try await result in transcriber.results { self?.handle(result) }
            } catch {
                NSLog("[SpeechAnalyzerTranscriber] results ended: %@", "\(error)")
                self?.recover(generation: gen)
            }
        })
        tasks.append(Task.detached { [weak self] in
            do {
                for try await result in detector.results {
                    guard let self else { return }
                    self.onSpeechDetected?(result.speechDetected, (self.baseHostTime ?? 0) + result.range.end.seconds)
                }
            } catch {}
        })
    }

    /// The analyzer can end with an error (e.g. "RecogRejected") while the app keeps running; without this the
    /// wake word and consent replies go deaf until the next source switch.
    private func recover(generation gen: Int) {
        guard gen == generation, let audio, recoveries < Self.maxRecoveries else { return }
        recoveries += 1
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, gen == self.generation else { return }
            self.tearDown()
            do { try await self.start(audio: audio) } catch { NSLog("[SpeechAnalyzerTranscriber] restart failed: %@", "\(error)") }
        }
    }

    private func handle(_ result: SpeechTranscriber.Result) {
        recoveries = 0
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseHostTime ?? CACurrentMediaTime()
        let start = base + result.range.start.seconds
        let end = base + result.range.end.seconds
        if result.isFinal {
            volatileText = ""
            guard !text.isEmpty else { return }
            let seg = TranscriptSegment(text: text, start: start, end: end, isFinal: true, speaker: speakerGuess?((start + end) / 2) ?? .none)
            window.append(seg)
            bus.publish(seg)
        } else {
            volatileText = text
            volatileBus.publish(VolatileText(text: text, t: end))
        }
    }

    func stop() {
        generation += 1
        audio = nil
        tearDown()
    }

    private func tearDown() {
        input?.finish()
        input = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let analyzer {
            Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        }
        analyzer = nil
        baseHostTime = nil
    }
}
