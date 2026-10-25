import XCTest
import AVFoundation
import UIKit
@testable import Familiar

/// Aligns the first five enrollment frames, attaches the 112×112 crops as PNGs, and checks that the detected eye
/// centers land on the ArcFace template eyes (±4 px) after the similarity transform.
final class AlignerSnapshotTests: XCTestCase {
    let appBundle = Bundle(for: AppCoordinator.self)

    func testFirstFiveEnrollmentCropsHitTemplateEyes() async throws {
        guard let url = appBundle.url(forResource: "enroll_marcus", withExtension: "mp4") else { throw XCTSkip("enroll_marcus.mp4 missing") }
        let frames = try await Self.readFrames(url: url, count: 5, stride: 6)
        XCTAssertEqual(frames.count, 5)
        let detector = FaceDetector(), aligner = FaceAligner.shared
        var aligned = 0, visionLandmarks = 0
        for (i, f) in frames.enumerated() {
            let res = detector.detectSync(f.pixelBuffer, orientation: f.orientation, timestamp: f.timestamp)
            guard let face = res.detections.max(by: { $0.box.height < $1.box.height }), let lm = face.landmarks else {
                XCTFail("frame \(i): no face with landmarks"); continue
            }
            let out = try XCTUnwrap(aligner.align(f.pixelBuffer, orientation: f.orientation, landmarks: lm))
            if face.landmarkSource == .vision { visionLandmarks += 1 }
            print("[aligner] frame \(i) landmarks(\(face.landmarkSource)) px: \(lm.points.map { String(format: "(%.0f,%.0f)", $0.x, $0.y) }.joined(separator: " ")) box=\(face.box)")
            let le = lm.leftEye.applying(out.transform), re = lm.rightEye.applying(out.transform)
            let tl = FaceAligner.template[0], tr = FaceAligner.template[1]
            print(String(format: "[aligner] frame %d eyes → (%.1f, %.1f) (%.1f, %.1f) template (%.1f, %.1f) (%.1f, %.1f) yaw=%@",
                         i, le.x, le.y, re.x, re.y, tl.x, tl.y, tr.x, tr.y, face.yawDegrees.map { String(format: "%.0f°", $0) } ?? "nil"))
            XCTAssertEqual(le.x, tl.x, accuracy: 4); XCTAssertEqual(le.y, tl.y, accuracy: 4)
            XCTAssertEqual(re.x, tr.x, accuracy: 4); XCTAssertEqual(re.y, tr.y, accuracy: 4)
            XCTAssertEqual(CVPixelBufferGetWidth(out.buffer), 112); XCTAssertEqual(CVPixelBufferGetHeight(out.buffer), 112)
            // Crops land in the xcresult as attachments; set TEST_RUNNER_ALIGNER_DUMP_DIR=/some/dir to also write them to disk.
            let dump = ProcessInfo.processInfo.environment["ALIGNER_DUMP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let dump { try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true) }
            if let cg = aligner.cgImage(out.buffer) {
                let a = XCTAttachment(image: UIImage(cgImage: cg)); a.name = "aligned_\(i).png"; a.lifetime = .keepAlways; add(a)
                if let dump { try? UIImage(cgImage: cg).pngData()?.write(to: dump.appendingPathComponent("aligned_\(i).png")) }
            }
            if let thumb = aligner.thumbnail(f.pixelBuffer, orientation: f.orientation, box: face.box), let img = UIImage(data: thumb) {
                XCTAssertEqual(img.size.width, 256, accuracy: 1); XCTAssertEqual(img.size.height, 256, accuracy: 1)
                if i == 0 { let a = XCTAttachment(image: img); a.name = "thumbnail_0.jpg"; a.lifetime = .keepAlways; add(a) }
                if let dump { try? thumb.write(to: dump.appendingPathComponent("thumbnail_\(i).jpg")) }
            }
            aligned += 1
        }
        XCTAssertEqual(aligned, 5)
        print("[aligner] \(visionLandmarks)/5 frames used Vision landmarks, \(5 - visionLandmarks)/5 fell back to box landmarks")
    }

    func testSimilarityTransformRecoversRotationAndScale() {
        let src = FaceAligner.template.map { CGPoint(x: $0.x * 3 + 100, y: $0.y * 3 + 50) }
        let m = FaceAligner.alignmentTransform(FaceLandmarks5(leftEye: src[0], rightEye: src[1], nose: src[2], mouthLeft: src[3], mouthRight: src[4]))
        for (p, t) in zip(src, FaceAligner.template) {
            let q = p.applying(m)
            XCTAssertEqual(q.x, t.x, accuracy: 0.01); XCTAssertEqual(q.y, t.y, accuracy: 0.01)
        }
        let fb = FaceAligner.fallbackTransform(leftEye: src[0], rightEye: src[1])
        let e = src[0].applying(fb)
        XCTAssertEqual(e.x, FaceAligner.template[0].x, accuracy: 1.0)
    }

    static func copy(_ f: Frame) -> Frame? {
        let src = f.pixelBuffer
        guard let dst = FaceAligner.makeBuffer(width: CVPixelBufferGetWidth(src), height: CVPixelBufferGetHeight(src)) else { return nil }
        CVPixelBufferLockBaseAddress(src, .readOnly); CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(src, .readOnly); CVPixelBufferUnlockBaseAddress(dst, []) }
        let rows = CVPixelBufferGetHeight(src), sb = CVPixelBufferGetBytesPerRow(src), db = CVPixelBufferGetBytesPerRow(dst)
        guard let s = CVPixelBufferGetBaseAddress(src), let d = CVPixelBufferGetBaseAddress(dst) else { return nil }
        for y in 0..<rows { memcpy(d + y * db, s + y * sb, min(sb, db)) }
        return Frame(pixelBuffer: dst, timestamp: f.timestamp, orientation: f.orientation, horizontalFOVDegrees: f.horizontalFOVDegrees, verticalFOVDegrees: f.verticalFOVDegrees)
    }

    static func readFrames(url: URL, count: Int, stride: Int) async throws -> [Frame] {
        let src = VideoFileFrameSource(url: url)
        src.loops = false; src.rate = 100
        let stream = src.subscribe()
        let box = PerceptionFixtureTests.Box<Frame>()
        // The reader recycles its pixel buffers, so keep deep copies instead of pinning the originals.
        let collector = Task { var n = 0; for await f in stream { defer { n += 1 }; if n % stride == 0, let c = copy(f) { box.add(c) }; if box.items.count >= count { break } } }
        try await src.start()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        src.stop(); collector.cancel()
        return Array(box.items.prefix(count))
    }
}
