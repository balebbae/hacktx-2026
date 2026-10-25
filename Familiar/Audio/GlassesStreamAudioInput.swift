import AVFoundation
import CoreMedia
import Foundation
import MWDATCamera
import os

/// Glasses microphone via the DAT camera stream (PCM 16 kHz mono). Dev only: it is not
/// beamformed and runs ~200 ms behind video, so the default audio path stays on the
/// phone mic. Enable with `GlassesFrameSource.Options.streamAudio`.
final class GlassesStreamAudioInput: AudioInput, @unchecked Sendable {
    private let chunks = EventBus<AudioChunk>(defaultPolicy: .bufferingNewest(64))
    private let level = OSAllocatedUnfairLock(initialState: Float(0))
    private let clock = OSAllocatedUnfairLock<(ptsBase: Double?, hostBase: Double)>(initialState: (nil, 0))

    var route: AudioRoute { .glassesStreamMic }
    var micLevel: Float { level.withLock { $0 } }

    func subscribe() -> AsyncStream<AudioChunk> { chunks.subscribe() }

    func handle(audioFrame: AudioFrame) {
        let buffer = audioFrame.pcmBuffer
        let samples = Self.floatSamples(buffer)
        guard !samples.isEmpty else { return }
        let now = CACurrentMediaTime()
        let pts = audioFrame.presentationTimeStamp
        let timestamp: TimeInterval = clock.withLock { c in
            guard pts.isValid && pts.isNumeric else { return now }
            let p = CMTimeGetSeconds(pts)
            if let base = c.ptsBase, p >= base { return c.hostBase + (p - base) }
            c.ptsBase = p
            c.hostBase = now
            return now
        }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        level.withLock { $0 = (sum / Float(samples.count)).squareRoot() }
        chunks.publish(AudioChunk(samples: samples, sampleRate: buffer.format.sampleRate, timestamp: timestamp))
    }

    static func floatSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return [] }
        if let f = buffer.floatChannelData { return Array(UnsafeBufferPointer(start: f[0], count: n)) }
        if let i16 = buffer.int16ChannelData {
            return UnsafeBufferPointer(start: i16[0], count: n).map { Float($0) / 32768 }
        }
        if let i32 = buffer.int32ChannelData {
            return UnsafeBufferPointer(start: i32[0], count: n).map { Float($0) / 2_147_483_648 }
        }
        return []
    }
}
