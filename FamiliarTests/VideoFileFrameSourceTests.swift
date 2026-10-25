import XCTest
import CoreVideo
@testable import Familiar

final class VideoFileFrameSourceTests: XCTestCase {
    func testEmitsBGRAFramesWithMonotonicTimestamps() async throws {
        let bundle = Bundle(for: AppCoordinator.self)
        guard let src = VideoFileFrameSource(fixtureNamed: "enroll_marcus", bundle: bundle) else {
            throw XCTSkip("Fixture enroll_marcus.mp4 is not in the bundle; add it to Familiar/Resources/Fixtures/")
        }
        src.loops = false
        src.rate = 8
        let stream = src.subscribe()
        try await src.start()
        var stamps: [TimeInterval] = []
        var format: OSType = 0
        var size = CGSize.zero
        for await f in stream {
            stamps.append(f.timestamp)
            format = CVPixelBufferGetPixelFormatType(f.pixelBuffer)
            size = CGSize(width: CVPixelBufferGetWidth(f.pixelBuffer), height: CVPixelBufferGetHeight(f.pixelBuffer))
            if stamps.count >= 10 { break }
        }
        src.stop()
        XCTAssertEqual(stamps.count, 10)
        XCTAssertEqual(stamps, stamps.sorted())
        XCTAssertEqual(format, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(size, CGSize(width: 720, height: 1280))
        XCTAssertEqual(src.horizontalFOVDegrees, 53)
    }

    func testMissingFixtureReturnsNil() {
        XCTAssertNil(VideoFileFrameSource(fixtureNamed: "does_not_exist", bundle: Bundle(for: AppCoordinator.self)))
    }
}
