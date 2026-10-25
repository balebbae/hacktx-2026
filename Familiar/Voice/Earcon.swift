import Foundation

/// 120 ms two-tone chime (880 Hz → 1320 Hz, 10 ms fades), generated once at 16 kHz.
enum Earcon {
    static let sampleRate: Double = 16_000
    static let duration: TimeInterval = 0.12

    static let samples: [Float] = make(sampleRate: sampleRate)

    static func make(sampleRate: Double, amplitude: Float = 0.35) -> [Float] {
        let total = Int(duration * sampleRate)
        let half = total / 2
        let fade = Int(0.010 * sampleRate)
        var out = [Float](repeating: 0, count: total)
        for i in 0..<total {
            let freq: Double = i < half ? 880 : 1320
            let local = i < half ? i : i - half
            let env: Float
            if local < fade { env = Float(local) / Float(fade) }
            else if local >= half - fade { env = Float(half - local) / Float(fade) }
            else { env = 1 }
            out[i] = amplitude * env * Float(sin(2 * Double.pi * freq * Double(i) / sampleRate))
        }
        return out
    }

    /// Chime followed by a short 40 ms gap, ready to be prepended to an utterance.
    static func prefix(for sampleRate: Double) -> [Float] {
        (sampleRate == Earcon.sampleRate ? samples : make(sampleRate: sampleRate)) + [Float](repeating: 0, count: Int(0.04 * sampleRate))
    }
}
