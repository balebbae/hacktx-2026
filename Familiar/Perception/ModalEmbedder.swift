import Foundation
import CoreVideo

/// Modal fallback: POSTs the aligned 112x112 crop as JPEG and parses `{"embedding": [...]}`. The crop is the only
/// image that ever leaves the phone and the server discards it. 2 s timeout, no retries (the caller falls back).
final class ModalEmbedder: EmbeddingProvider, @unchecked Sendable {
    let modelID = "w600k_mbf"
    let dimension = 512
    let url: URL
    let healthURL: URL?
    let key: String?
    let secret: String?
    let session: URLSession
    private let aligner = FaceAligner.shared
    private(set) var lastMillis: Double = 0
    private(set) var lastServerMillis: Double?

    struct Response: Decodable { let embedding: [Float]; let model: String?; let ms: Double?; let error: String? }

    enum ModalError: Error, LocalizedError {
        case http(Int, String), server(String), badImage, wrongDimension(Int)
        var errorDescription: String? {
            switch self {
            case let .http(code, body): return "Modal HTTP \(code): \(body.prefix(120))"
            case let .server(s): return "Modal: \(s)"
            case .badImage: return "Modal: could not encode the crop"
            case let .wrongDimension(n): return "Modal: expected 512 floats, got \(n)"
            }
        }
    }

    init(url: URL, key: String?, secret: String?, healthURL: URL? = nil, timeout: TimeInterval = 2) {
        self.url = url; self.key = key; self.secret = secret; self.healthURL = healthURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// From `Secrets.xcconfig` (MODAL_EMBED_URL / MODAL_KEY / MODAL_SECRET). Nil when the URL is not configured.
    convenience init?() {
        guard let url = Secrets.modalEmbedURL else { return nil }
        let health = URL(string: url.absoluteString.replacingOccurrences(of: "-embed.", with: "-health."))
        self.init(url: url, key: Secrets.modalKey, secret: Secrets.modalSecret, healthURL: health == url ? nil : health)
    }

    private func request(_ u: URL, method: String) -> URLRequest {
        var r = URLRequest(url: u)
        r.httpMethod = method
        if let key { r.setValue(key, forHTTPHeaderField: "Modal-Key") }
        if let secret { r.setValue(secret, forHTTPHeaderField: "Modal-Secret") }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    func embed(_ alignedFace112: CVPixelBuffer) async throws -> [Float] {
        guard let jpeg = aligner.jpeg(alignedFace112, quality: 0.92) else { throw ModalError.badImage }
        return try await embed(jpegData: jpeg)
    }

    func embed(jpegData: Data) async throws -> [Float] {
        var r = request(url, method: "POST")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["image_b64": jpegData.base64EncodedString()])
        let t0 = Date()
        let (data, resp) = try await session.data(for: r)
        lastMillis = Date().timeIntervalSince(t0) * 1000
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ModalError.http(code, String(data: data, encoding: .utf8) ?? "") }
        if let err = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] { throw ModalError.server(err) }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        if let e = parsed.error { throw ModalError.server(e) }
        guard parsed.embedding.count == dimension else { throw ModalError.wrongDimension(parsed.embedding.count) }
        lastServerMillis = parsed.ms
        return Matcher.normalized(parsed.embedding)
    }

    func health() async -> Bool {
        guard let healthURL else { return false }
        guard let (data, resp) = try? await session.data(for: request(healthURL, method: "GET")) else { return false }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return (try? JSONDecoder().decode([String: AnyDecodable].self, from: data))?["ok"]?.bool == true
    }

    struct AnyDecodable: Decodable {
        let bool: Bool?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            bool = try? c.decode(Bool.self)
        }
    }
}
