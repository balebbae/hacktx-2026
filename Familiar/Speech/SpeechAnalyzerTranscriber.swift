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

    init() {}

    func subscribe() -> AsyncStream<TranscriptSegment> { bus.subscribe() }
    func subscribeVolatile() -> AsyncStream<VolatileText> { volatileBus.subscribe() }
    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] { window.recent(seconds: seconds, now: CACurrentMediaTime()) }

    func start(audio: AudioInput) async throws {
        guard analyzer == nil else { return }
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
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: AudioBuffers.chunkFormat) ?? AudioBuffers.chunkFormat
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        try await analyzer.start(inputSequence: stream)

        let chunks = audio.subscribe()
        tasks.append(Task.detached { [weak self] in
            var converter: AVAudioConverter?
            for await chunk in chunks {
                guard let self else { return }
                let base = self.baseHostTime ?? chunk.timestamp
                if self.baseHostTime == nil { self.baseHostTime = base }
                guard let buffer = AudioBuffers.buffer(for: chunk, in: format, converter: &converter) else { continue }
                continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: CMTime(seconds: chunk.timestamp - base, preferredTimescale: 48_000)))
            }
        })
        tasks.append(Task.detached { [weak self] in
            do {
                for try await result in transcriber.results { self?.handle(result) }
            } catch { NSLog("[SpeechAnalyzerTranscriber] results ended: %@", "\(error)") }
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

    private func handle(_ result: SpeechTranscriber.Result) {
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
