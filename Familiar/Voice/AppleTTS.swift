import Foundation
import AVFoundation

/// On-device fallback: renders `AVSpeechSynthesizer` output to PCM buffers (no direct playback) and converts
/// them to 16 kHz mono Float32 so they go through the same engine and report the same window as ElevenLabs.
final class AppleTTS: NSObject, SpeechSynthesizer, @unchecked Sendable {
    enum Failure: Error { case noAudio, conversionFailed }

    let id = "apple"
    let voice: AVSpeechSynthesisVoice?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    static let sampleRate: Double = 16_000
    private let synthesizer = AVSpeechSynthesizer()
    private let serial = AsyncSemaphore(count: 1)

    override init() {
        voice = AppleTTS.bestVoice()
        super.init()
    }

    /// Prefer premium, then enhanced, then any en-US voice.
    static func bestVoice(language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 2
            case .enhanced: return 1
            default: return 0
            }
        }
        return voices.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        await serial.wait()
        defer { Task { await serial.signal() } }
        let buffers = try await render(text)
        guard let first = buffers.first else { throw Failure.noAudio }
        let samples = try AppleTTS.convert(buffers, from: first.format, to: AppleTTS.sampleRate)
        guard !samples.isEmpty else { throw Failure.noAudio }
        return SynthesizedAudio(samples: samples, sampleRate: AppleTTS.sampleRate, source: id)
    }

    private func render(_ text: String) async throws -> [AVAudioPCMBuffer] {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        let collector = Collector()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[AVAudioPCMBuffer], Error>) in
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    collector.finish { cont.resume(returning: $0) }
                } else {
                    collector.append(pcm)
                }
            }
        }
    }

    static func convert(_ buffers: [AVAudioPCMBuffer], from format: AVAudioFormat, to sampleRate: Double) throws -> [Float] {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { throw Failure.conversionFailed }
        converter.primeMethod = .none
        var out: [Float] = []
        for buffer in buffers {
            let ratio = sampleRate / format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw Failure.conversionFailed }
            var fed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if let error { throw error }
            if let ch = converted.floatChannelData { out.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(converted.frameLength))) }
        }
        return out
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffers: [AVAudioPCMBuffer] = []
        private var finished = false
        func append(_ b: AVAudioPCMBuffer) { lock.lock(); buffers.append(b); lock.unlock() }
        func finish(_ body: ([AVAudioPCMBuffer]) -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            body(buffers)
        }
    }
}
