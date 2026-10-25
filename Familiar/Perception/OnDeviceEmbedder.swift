import Foundation
import CoreVideo
import CryptoKit
import QuartzCore
import OnnxRuntimeBindings

/// InsightFace `w600k_mbf` through ONNX Runtime. One `ORTEnv` and one `ORTSession`, created lazily on first use.
/// Input/output names are read from the session. CPU EP by default; CoreML EP behind `provider`.
final class OnDeviceEmbedder: EmbeddingProvider, @unchecked Sendable {
    enum Provider: String { case cpu, coreML }

    let modelID = "w600k_mbf"
    let dimension = 512
    let modelURL: URL
    let provider: Provider

    private let lock = NSLock()
    private var env: ORTEnv?
    private var session: ORTSession?
    private(set) var inputName = ""
    private(set) var outputName = ""
    private(set) var lastMillis: Double = 0
    private(set) var totalMillis: Double = 0
    private(set) var count = 0
    var averageMillis: Double { count > 0 ? totalMillis / Double(count) : 0 }

    init(modelURL: URL, provider: Provider = .cpu) { self.modelURL = modelURL; self.provider = provider }

    convenience init?(bundle: Bundle = .main, provider: Provider = .cpu) {
        guard let url = bundle.url(forResource: "w600k_mbf", withExtension: "onnx") else { return nil }
        self.init(modelURL: url, provider: provider)
    }

    lazy var modelSHA256: String = {
        guard let data = try? Data(contentsOf: modelURL) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }()

    enum EmbedError: Error, LocalizedError {
        case badInput(String), noOutput, badOutput(Int)
        var errorDescription: String? {
            switch self {
            case let .badInput(s): return "OnDeviceEmbedder: bad input (\(s))"
            case .noOutput: return "OnDeviceEmbedder: session returned no output"
            case let .badOutput(n): return "OnDeviceEmbedder: expected 512 floats, got \(n)"
            }
        }
    }

    /// Creates the session (slow, ~100-300 ms) and runs one zero tensor so the first real call is fast.
    func warmUp() throws {
        _ = try ensureSession()
        let zeros = NSMutableData(length: 3 * 112 * 112 * MemoryLayout<Float>.size)!
        _ = try run(tensor: zeros)
    }

    private func ensureSession() throws -> ORTSession {
        lock.lock(); defer { lock.unlock() }
        if let session { return session }
        let env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(2)
        try opts.setGraphOptimizationLevel(.all)
        try opts.setLogSeverityLevel(.warning)
        if provider == .coreML {
            try opts.appendExecutionProvider("CoreML", providerOptions: ["ModelFormat": "MLProgram", "MLComputeUnits": "CPUAndNeuralEngine", "RequireStaticInputShapes": "1"])
        }
        let s = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
        guard let i = try s.inputNames().first, let o = try s.outputNames().first else { throw EmbedError.noOutput }
        inputName = i; outputName = o
        self.env = env; self.session = s
        return s
    }

    func embed(_ alignedFace112: CVPixelBuffer) async throws -> [Float] {
        let tensor = try Self.preprocess(alignedFace112)
        return try run(tensor: tensor)
    }

    /// Synchronous inference, serialized by the lock. Returns the L2-normalised 512-vector.
    func run(tensor: NSMutableData) throws -> [Float] {
        let session = try ensureSession()
        let t0 = CACurrentMediaTime()
        let input = try ORTValue(tensorData: tensor, elementType: .float, shape: [1, 3, 112, 112])
        let outputs: [String: ORTValue]
        lock.lock()
        do { outputs = try session.run(withInputs: [inputName: input], outputNames: [outputName], runOptions: nil) }
        catch { lock.unlock(); throw error }
        lock.unlock()
        guard let out = outputs[outputName] else { throw EmbedError.noOutput }
        let data = try out.tensorData() as Data
        let n = data.count / MemoryLayout<Float>.size
        guard n == dimension else { throw EmbedError.badOutput(n) }
        let raw = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let ms = (CACurrentMediaTime() - t0) * 1000
        lock.lock(); lastMillis = ms; totalMillis += ms; count += 1; lock.unlock()
        return Matcher.normalized(raw)
    }

    /// BGRA 112x112 → float32 NCHW RGB planes, `(x - 127.5) / 127.5`.
    static func preprocess(_ pb: CVPixelBuffer) throws -> NSMutableData {
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard w == 112, h == 112 else { throw EmbedError.badInput("size \(w)x\(h)") }
        let fmt = CVPixelBufferGetPixelFormatType(pb)
        guard fmt == kCVPixelFormatType_32BGRA || fmt == kCVPixelFormatType_32ARGB || fmt == kCVPixelFormatType_32RGBA else { throw EmbedError.badInput("format \(fmt)") }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { throw EmbedError.badInput("no base address") }
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let plane = w * h
        let data = NSMutableData(length: 3 * plane * MemoryLayout<Float>.size)!
        let out = data.mutableBytes.bindMemory(to: Float.self, capacity: 3 * plane)
        let (ri, gi, bi): (Int, Int, Int)
        switch fmt {
        case kCVPixelFormatType_32ARGB: (ri, gi, bi) = (1, 2, 3)
        case kCVPixelFormatType_32RGBA: (ri, gi, bi) = (0, 1, 2)
        default: (ri, gi, bi) = (2, 1, 0)
        }
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let p = row.advanced(by: x * 4)
                let i = y * w + x
                out[i] = (Float(p[ri]) - 127.5) / 127.5
                out[plane + i] = (Float(p[gi]) - 127.5) / 127.5
                out[2 * plane + i] = (Float(p[bi]) - 127.5) / 127.5
            }
        }
        return data
    }
}
