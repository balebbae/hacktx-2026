import Foundation
import os

/// Energy VAD plus a loudness-based user/other guess. 20 ms frames, adaptive noise floor + 8 dB, 250 ms hangover.
/// `calibrateUser(seconds:)` records the wearer's RMS; speech louder than 0.6 × userRMS is `.user`, else `.other`.
/// When an iOS 26 `SpeechDetector` is available its verdict is preferred for `isSpeech` (`noteExternalSpeech`).
final class LoudnessSplit: VoiceActivity, @unchecked Sendable {
    typealias Sample = (isSpeech: Bool, guess: SpeakerGuess, t: TimeInterval)

    let sampleRate: Double
    let frameSeconds: TimeInterval = 0.020
    var thresholdDB: Float = 8
    var hangover: TimeInterval = 0.25
    var userFraction: Float = 0.6
    /// Used until `calibrateUser` has run (typical close-mic speech RMS).
    var userRMS: Float = 0.08
    var isCalibrated: Bool { state.withLock { $0.calibrated } }

    private struct State {
        var noiseFloorDB: Float = -60
        var carry: [Float] = []
        var carryTime: TimeInterval = 0
        var speechUntil: TimeInterval = -1
        var lastSpeech = false
        var lastGuess: SpeakerGuess = .none
        var history: [(t: TimeInterval, guess: SpeakerGuess)] = []
        var calibrating: (until: TimeInterval, rms: [Float])?
        var calibrated = false
        var externalSpeech: (isSpeech: Bool, at: TimeInterval)?
        var lastFrameTime: TimeInterval = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let bus = EventBus<Sample>()
    private var task: Task<Void, Never>?

    init(sampleRate: Double = 16_000) { self.sampleRate = sampleRate }

    func subscribe() -> AsyncStream<Sample> { bus.subscribe() }

    /// Attach to a raw (un-gated) audio input.
    func start(audio: AudioInput) {
        guard task == nil else { return }
        let stream = audio.subscribe()
        task = Task.detached { [weak self] in
            for await chunk in stream { self?.process(chunk) }
        }
    }

    func stop() { task?.cancel(); task = nil }

    var current: Sample { state.withLock { ($0.lastSpeech, $0.lastGuess, $0.lastFrameTime) } }

    /// The guess that was in force at `t` (used to label transcript segments).
    func guess(at t: TimeInterval) -> SpeakerGuess {
        state.withLock { s in
            s.history.last(where: { $0.t <= t })?.guess ?? s.history.first?.guess ?? .none
        }
    }

    func calibrateUser(seconds: Double) async {
        let start = state.withLock { s -> TimeInterval in
            let now = s.lastFrameTime
            s.calibrating = (until: now + seconds, rms: [])
            return now
        }
        let deadline = Date().addingTimeInterval(seconds + 0.5)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let done = state.withLock { s in s.calibrating == nil || s.lastFrameTime >= start + seconds }
            if done { break }
        }
        finishCalibration()
    }

    /// Feed a known-loudness sample directly (tests, or when the UI drives calibration from a buffer).
    func calibrateUser(with samples: [Float]) {
        let rms = LoudnessSplit.rms(samples)
        state.withLock { s in s.calibrated = true; s.calibrating = nil }
        if rms > 0 { userRMS = rms }
    }

    private func finishCalibration() {
        let rmsValues = state.withLock { s -> [Float] in
            let v = s.calibrating?.rms ?? []
            s.calibrating = nil
            return v
        }
        let voiced = rmsValues.filter { $0 > 0.005 }.sorted()
        guard !voiced.isEmpty else { return }
        userRMS = voiced[voiced.count / 2]       // median of voiced frames
        state.withLock { $0.calibrated = true }
    }

    /// Verdict from `SpeechDetector` (iOS 26); preferred over the energy VAD while fresh (< 1 s old).
    func noteExternalSpeech(_ isSpeech: Bool, at t: TimeInterval) {
        state.withLock { $0.externalSpeech = (isSpeech, t) }
    }

    func process(_ chunk: AudioChunk) {
        let frameLen = Int(frameSeconds * sampleRate)
        var outputs: [Sample] = []
        state.withLock { s in
            if s.carry.isEmpty { s.carryTime = chunk.timestamp }
            s.carry.append(contentsOf: chunk.samples)
            var offset = 0
            while s.carry.count - offset >= frameLen {
                let frame = s.carry[offset..<(offset + frameLen)]
                let t = s.carryTime + Double(offset) / sampleRate
                offset += frameLen
                if let out = analyze(frame: Array(frame), at: t, s: &s) { outputs.append(out) }
            }
            s.carry.removeFirst(offset)
            s.carryTime += Double(offset) / sampleRate
        }
        for o in outputs { bus.publish(o) }
    }

    private func analyze(frame: [Float], at t: TimeInterval, s: inout State) -> Sample? {
        let rms = LoudnessSplit.rms(frame)
        let db = LoudnessSplit.decibels(rms)
        s.lastFrameTime = t
        if var c = s.calibrating {
            c.rms.append(rms)
            s.calibrating = c
        }
        var speechNow = db > s.noiseFloorDB + thresholdDB
        if let ext = s.externalSpeech, t - ext.at < 1.0 { speechNow = ext.isSpeech }
        if speechNow {
            s.speechUntil = t + hangover
        } else {
            // Adaptive floor: track quiet frames quickly downward, slowly upward.
            s.noiseFloorDB = db < s.noiseFloorDB ? s.noiseFloorDB * 0.8 + db * 0.2 : s.noiseFloorDB * 0.98 + db * 0.02
        }
        let isSpeech = t <= s.speechUntil
        var guess = s.lastGuess
        if speechNow {
            guess = rms >= userFraction * userRMS ? .user : .other
        } else if !isSpeech {
            guess = .none
        }
        let changed = isSpeech != s.lastSpeech || guess != s.lastGuess
        s.lastSpeech = isSpeech
        s.lastGuess = guess
        if changed {
            s.history.append((t, guess))
            if let cutoff = s.history.last.map({ $0.t - 90 }) { s.history.removeAll { $0.t < cutoff } }
            return (isSpeech, guess, t)
        }
        return nil
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var acc: Float = 0
        for s in samples { acc += s * s }
        return (acc / Float(samples.count)).squareRoot()
    }

    static func decibels(_ rms: Float) -> Float { 20 * log10(max(rms, 1e-6)) }
}
