import XCTest
import CryptoKit
@testable import Familiar

/// Proves the bundled ORT model loads, that I/O names come from the session, and that our preprocessing matches
/// the Python reference (S9's `modal/export_test_vector.py` vector for the same aligned 112×112 JPEG).
final class OnDeviceEmbedderTests: XCTestCase {
    let appBundle = Bundle(for: AppCoordinator.self)

    func testModelHashAndRuntimeIONames() throws {
        let url = try XCTUnwrap(appBundle.url(forResource: "w600k_mbf", withExtension: "onnx"), "model not bundled")
        let data = try Data(contentsOf: url)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        print("[embedder] model w600k_mbf.onnx bytes=\(data.count) sha256=\(sha)")
        XCTAssertEqual(sha, "9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f")
        let e = try XCTUnwrap(OnDeviceEmbedder(bundle: appBundle))
        try e.warmUp()
        print("[embedder] provider=\(e.provider) input=\(e.inputName) output=\(e.outputName)")
        XCTAssertFalse(e.inputName.isEmpty); XCTAssertFalse(e.outputName.isEmpty)
    }

    func testMatchesPythonReferenceVectorAndReportsLatency() async throws {
        let e = try XCTUnwrap(OnDeviceEmbedder(bundle: appBundle))
        let testBundle = Bundle(for: Self.self)
        guard let jpg = testBundle.url(forResource: "aligned112", withExtension: "jpg"),
              let json = testBundle.url(forResource: "aligned112_embedding", withExtension: "json") else {
            throw XCTSkip("aligned112.jpg / aligned112_embedding.json not in test bundle")
        }
        struct Ref: Decodable { let embedding: [Float] }
        let ref = try JSONDecoder().decode(Ref.self, from: Data(contentsOf: json)).embedding
        let pb = try XCTUnwrap(FaceAligner.shared.pixelBuffer(from: Data(contentsOf: jpg)))
        XCTAssertEqual(CVPixelBufferGetWidth(pb), 112); XCTAssertEqual(CVPixelBufferGetHeight(pb), 112)
        let v = try await e.embed(pb)
        XCTAssertEqual(v.count, 512)
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 1e-3)
        let cos = Matcher.cosine(v, Matcher.normalized(ref))
        print("[embedder] cosine(iOS ORT, python reference) = \(cos)")
        XCTAssertGreaterThan(cos, 0.98, "preprocessing diverges from the Python reference (JPEG decode differences allow ~0.99)")

        var ms: [Double] = []
        for _ in 0..<20 {
            let t0 = CACurrentMediaTime(); _ = try await e.embed(pb); ms.append((CACurrentMediaTime() - t0) * 1000)
        }
        ms.sort()
        print(String(format: "[embedder] ms/embedding (Simulator, %@): median %.1f  p90 %.1f  min %.1f  session-avg %.1f over %d",
                     "\(e.provider)", ms[ms.count / 2], ms[Int(Double(ms.count) * 0.9)], ms[0], e.averageMillis, e.count))
    }
}
