import Foundation
import AVFoundation
import QuartzCore

// Types added by S3 for the audio module (Core is frozen).

enum AudioEngineError: Error, Equatable {
    case hfpBlockedByGlassesStream
    case noInput
    case formatUnsupported
}

/// Converts arbitrary-format `AVAudioPCMBuffer`s from an input tap into 16 kHz mono Float32 `AudioChunk`s with
/// host-clock timestamps. Pure enough to be exercised with synthetic buffers in the Simulator.
final class AudioChunker {
    static let targetRate: Double = 16_000
    let inputFormat: AVAudioFormat
    let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    init?(inputFormat: AVAudioFormat) {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioChunker.targetRate, channels: 1, interleaved: false) else { return nil }
        self.inputFormat = inputFormat
        self.outputFormat = out
        if inputFormat.sampleRate == out.sampleRate && inputFormat.channelCount == 1 && inputFormat.commonFormat == .pcmFormatFloat32 {
            converter = nil
        } else {
            guard let c = AVAudioConverter(from: inputFormat, to: out) else { return nil }
            c.primeMethod = .none
            converter = c
        }
    }

    /// `hostTime` of the buffer's first frame (from `AVAudioTime`), or nil to use the current host clock.
    func chunk(_ buffer: AVAudioPCMBuffer, when: AVAudioTime?) -> AudioChunk? {
        let timestamp: TimeInterval = (when?.isHostTimeValid ?? false) ? AVAudioTime.seconds(forHostTime: when!.hostTime) : CACurrentMediaTime()
        guard let samples = convert(buffer), !samples.isEmpty else { return nil }
        return AudioChunk(samples: samples, sampleRate: AudioChunker.targetRate, timestamp: timestamp)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        guard let converter else {
            guard let ch = buffer.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
        }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard error == nil, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }
}

/// `AudioInput` backed by an `EventBus`. The controller owns one raw instance (VAD, ring buffer) and one gated
/// instance whose samples are zeroed while the app is speaking and for 300 ms afterwards (the transcriber's feed).
final class EngineAudioInput: AudioInput, @unchecked Sendable {
    private let bus = EventBus<AudioChunk>(defaultPolicy: .bufferingNewest(64))
    private let levelLock = NSLock()
    private var level: Float = 0
    private var levelUpdatedAt: TimeInterval = 0
    private let routeProvider: () -> AudioRoute
    /// When set, chunks for which it returns true are replaced with silence of the same length and timestamp.
    let gate: ((AudioChunk) -> Bool)?

    init(route: @escaping () -> AudioRoute, gate: ((AudioChunk) -> Bool)? = nil) {
        self.routeProvider = route
        self.gate = gate
    }

    func subscribe() -> AsyncStream<AudioChunk> { bus.subscribe() }
    var route: AudioRoute { routeProvider() }
    var micLevel: Float { levelLock.lock(); defer { levelLock.unlock() }; return level }
    var subscriberCount: Int { bus.subscriberCount }

    func publish(_ chunk: AudioChunk) {
        var out = chunk
        if let gate, gate(chunk) {
            out = AudioChunk(samples: [Float](repeating: 0, count: chunk.samples.count), sampleRate: chunk.sampleRate, timestamp: chunk.timestamp)
        }
        updateLevel(chunk)
        bus.publish(out)
    }

    /// RMS, refreshed at most 10× per second.
    private func updateLevel(_ chunk: AudioChunk) {
        levelLock.lock(); defer { levelLock.unlock() }
        guard chunk.timestamp - levelUpdatedAt >= 0.1 || levelUpdatedAt == 0 else { return }
        level = LoudnessSplit.rms(chunk.samples)
        levelUpdatedAt = chunk.timestamp
    }

    func finish() { bus.finishAll() }
}

enum AudioFactory {
    /// The single engine owner. S5 calls this once from `Services.make` and passes it as `audioInput`
    /// (`controller.rawInput`), `PCMPlayback` for `VoiceFactory.makeSpeaker`, and `controller.transcriberInput`
    /// to the transcriber.
    static func makeEngine(route: AudioRoute = .phoneMicGlassesA2DP) -> AudioEngineController {
        AudioEngineController(route: route)
    }

    static func makeVoiceActivity(audio: AudioInput) -> LoudnessSplit {
        let vad = LoudnessSplit()
        vad.start(audio: audio)
        return vad
    }
}
