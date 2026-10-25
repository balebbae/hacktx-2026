import Foundation
import AVFoundation
import Speech

/// iOS 18 fallback: `SFSpeechRecognizer` with on-device recognition, restarted every `restartInterval` (50 s).
/// Words that have been stable for `settleSeconds` are published as final segments so consumers never wait for the
/// recognizer's own (late) final result. The only path that needs `SFSpeechRecognizer.requestAuthorization`.
final class SFSpeechTranscriber: NSObject, Transcriber, VolatileTextSource, @unchecked Sendable {
    var speakerGuess: ((TimeInterval) -> SpeakerGuess)?
    var restartInterval: TimeInterval = 50
    var settleSeconds: TimeInterval = 1.5
    private(set) var volatileText = ""

    private let window = TranscriptWindow()
    private let bus = EventBus<TranscriptSegment>()
    private let volatileBus = EventBus<VolatileText>()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var feeder: Task<Void, Never>?
    private var requestStartedAt: TimeInterval?
    private var publishedWords = 0
    private let lock = NSLock()

    override init() { super.init() }

    func subscribe() -> AsyncStream<TranscriptSegment> { bus.subscribe() }
    func subscribeVolatile() -> AsyncStream<VolatileText> { volatileBus.subscribe() }
    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] { window.recent(seconds: seconds, now: CACurrentMediaTime()) }

    /// False in tests: a system permission alert would hang the test host.
    var promptsForAuthorization = true

    static func authorize(prompt: Bool = true) async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined || !prompt { return current }
        return await withCheckedContinuation { cont in SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) } }
    }

    func start(audio: AudioInput) async throws {
        guard feeder == nil else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { throw TranscriberError.unavailable("SFSpeechRecognizer unavailable") }
        guard recognizer.supportsOnDeviceRecognition else { throw TranscriberError.unavailable("on-device SFSpeechRecognizer not supported here") }
        guard await SFSpeechTranscriber.authorize(prompt: promptsForAuthorization) == .authorized else { throw TranscriberError.notAuthorized }
        self.recognizer = recognizer
        let chunks = audio.subscribe()
        feeder = Task.detached { [weak self] in
            for await chunk in chunks {
                guard let self else { return }
                self.feed(chunk)
            }
        }
    }

    private func feed(_ chunk: AudioChunk) {
        lock.lock(); defer { lock.unlock() }
        if request == nil || (requestStartedAt.map { chunk.timestamp - $0 >= restartInterval } ?? false) { beginRequestLocked(at: chunk.timestamp) }
        guard let buffer = AudioBuffers.buffer(samples: chunk.samples, sampleRate: chunk.sampleRate) else { return }
        request?.append(buffer)
    }

    private func beginRequestLocked(at t: TimeInterval) {
        request?.endAudio()
        task?.finish()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        request = req
        requestStartedAt = t
        publishedWords = 0
        let base = t
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result { self.handle(result, base: base) }
            if error != nil || (result?.isFinal ?? false) { self.lock.lock(); if self.requestStartedAt == base { self.request = nil }; self.lock.unlock() }
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult, base: TimeInterval) {
        let segments = result.bestTranscription.segments
        guard let last = segments.last else { return }
        let latestEnd = last.timestamp + last.duration
        volatileText = result.bestTranscription.formattedString
        volatileBus.publish(VolatileText(text: volatileText, t: base + latestEnd))
        lock.lock()
        let from = publishedWords
        var settled = segments.enumerated().filter { i, s in i >= from && (result.isFinal || latestEnd - (s.timestamp + s.duration) >= settleSeconds) }.map(\.element)
        if !result.isFinal, settled.count < 3 { settled = [] }
        guard let first = settled.first, let end = settled.last else { lock.unlock(); return }
        publishedWords = from + settled.count
        lock.unlock()
        let seg = TranscriptSegment(text: settled.map(\.substring).joined(separator: " "), start: base + first.timestamp, end: base + end.timestamp + end.duration, isFinal: true, speaker: speakerGuess?(base + (first.timestamp + end.timestamp + end.duration) / 2) ?? .none)
        window.append(seg)
        bus.publish(seg)
    }

    func stop() {
        feeder?.cancel(); feeder = nil
        lock.lock()
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        requestStartedAt = nil
        lock.unlock()
    }
}
