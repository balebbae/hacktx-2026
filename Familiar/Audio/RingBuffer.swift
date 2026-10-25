import Foundation
import os

/// 30 s of 16 kHz Float32 with host timestamps. `slice(from:to:)` returns the samples in a time range (wrapping
/// around), `writeWAV(url:)` dumps the whole buffer as 16-bit PCM (the consent clip).
final class RingBuffer: @unchecked Sendable {
    let sampleRate: Double
    let capacity: Int
    private var samples: [Float]
    private var writeIndex = 0
    private var filled = 0
    /// Host time of the sample at `writeIndex` (the next one to be written).
    private var nextTimestamp: TimeInterval?
    private let lock = NSLock()

    init(seconds: TimeInterval = 30, sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
        self.capacity = Int(seconds * sampleRate)
        self.samples = [Float](repeating: 0, count: capacity)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return filled }

    /// Time of the oldest and newest sample currently held.
    var timeRange: ClosedRange<TimeInterval>? {
        lock.lock(); defer { lock.unlock() }
        guard let next = nextTimestamp, filled > 0 else { return nil }
        return (next - Double(filled) / sampleRate)...(next - 1 / sampleRate)
    }

    func write(_ chunk: AudioChunk) { write(chunk.samples, at: chunk.timestamp) }

    func write(_ data: [Float], at timestamp: TimeInterval) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var src = data[...]
        if data.count > capacity { src = data[(data.count - capacity)...] }
        for s in src {
            samples[writeIndex] = s
            writeIndex = (writeIndex + 1) % capacity
        }
        filled = min(capacity, filled + src.count)
        nextTimestamp = timestamp + Double(data.count) / sampleRate
    }

    func slice(from: TimeInterval, to: TimeInterval) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard let next = nextTimestamp, filled > 0, to > from else { return [] }
        let oldest = next - Double(filled) / sampleRate
        let start = max(from, oldest), end = min(to, next)
        guard end > start else { return [] }
        let startOffset = Int(((start - oldest) * sampleRate).rounded())
        let n = Int(((end - start) * sampleRate).rounded())
        guard n > 0 else { return [] }
        let base = (writeIndex - filled + capacity) % capacity
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = samples[(base + startOffset + i) % capacity] }
        return out
    }

    /// Everything held, oldest first.
    func all() -> [Float] {
        guard let r = timeRange else { return [] }
        return slice(from: r.lowerBound, to: r.upperBound + 1 / sampleRate)
    }

    func writeWAV(url: URL, from: TimeInterval? = nil, to: TimeInterval? = nil) throws {
        let data: [Float]
        if let from, let to { data = slice(from: from, to: to) } else { data = all() }
        try RingBuffer.wavData(samples: data, sampleRate: sampleRate).write(to: url, options: .atomic)
    }

    static func wavData(samples: [Float], sampleRate: Double) -> Data {
        let pcm = PCM16.encode(samples)
        var d = Data()
        func u32(_ v: UInt32) { var le = v.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        func u16(_ v: UInt16) { var le = v.littleEndian; d.append(Data(bytes: &le, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
