import Foundation
import CryptoKit

/// Disk cache of synthesized phrases: `Caches/tts/<sha256(voiceID|model|text)>.pcm`, raw 16-bit LE mono 16 kHz.
final class PhraseCache: @unchecked Sendable {
    let directory: URL
    private let fm = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tts", isDirectory: true)
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func key(voiceID: String, model: String, text: String) -> String {
        let digest = SHA256.hash(data: Data("\(voiceID)|\(model)|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func url(voiceID: String, model: String, text: String) -> URL {
        directory.appendingPathComponent(PhraseCache.key(voiceID: voiceID, model: model, text: text)).appendingPathExtension("pcm")
    }

    func has(voiceID: String, model: String, text: String) -> Bool {
        let u = url(voiceID: voiceID, model: model, text: text)
        let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    /// Returns the cached PCM as Float samples, or nil on a miss (empty files count as misses).
    func samples(voiceID: String, model: String, text: String) -> [Float]? {
        guard let data = try? Data(contentsOf: url(voiceID: voiceID, model: model, text: text)), !data.isEmpty else { return nil }
        return PCM16.decode(data)
    }

    func store(_ pcm16: Data, voiceID: String, model: String, text: String) {
        guard !pcm16.isEmpty else { return }
        try? pcm16.write(to: url(voiceID: voiceID, model: model, text: text), options: .atomic)
    }

    func store(samples: [Float], voiceID: String, model: String, text: String) {
        store(PCM16.encode(samples), voiceID: voiceID, model: model, text: text)
    }

    func files() -> [URL] {
        ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []).filter { $0.pathExtension == "pcm" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func clear() { for f in files() { try? fm.removeItem(at: f) } }
}

/// 16-bit little-endian PCM <-> Float32 helpers shared by the cache, ElevenLabs and the ring buffer's WAV writer.
enum PCM16 {
    static func decode(_ data: Data) -> [Float] {
        let count = data.count / 2
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            for i in 0..<count {
                let v = Int16(littleEndian: base.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                out[i] = Float(v) / 32768
            }
        }
        return out
    }

    static func encode(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!
            for (i, s) in samples.enumerated() {
                let clamped = max(-1, min(1, s))
                let v = Int16((clamped * 32767).rounded()).littleEndian
                base.storeBytes(of: v, toByteOffset: i * 2, as: Int16.self)
            }
        }
        return data
    }
}
