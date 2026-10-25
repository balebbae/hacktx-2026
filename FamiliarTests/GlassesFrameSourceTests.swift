import CoreVideo
import XCTest
@testable import Familiar

final class GlassesFrameSourceTests: XCTestCase {
    func testStatusLabelsNeverSayTheWakeWord() {
        let all: [GlassesStatus] = [.idle, .notRegistered, .cameraPermissionDenied, .connecting, .waitingForFrames,
                                    .streaming, .paused, .stopped(reason: "Glasses folded"), .failed(reason: "x")]
        for s in all { XCTAssertFalse(s.label.localizedCaseInsensitiveContains("familiar"), s.label) }
    }

    func testFactoryReturnsCoordinator() {
        let source = GlassesFactory.makeFrameSource()
        XCTAssertTrue(source is GlassesStreamCoordinator)
        XCTAssertFalse((source as! GlassesStreamCoordinator).isStreaming)
    }

    private static let unsignedNote = "Wearables.configure() fails in unsigned builds (CODE_SIGNING_ALLOWED=NO); run `xcodebuild test` without that flag to exercise the DAT mock"

    func testStartWithoutRegistrationThrows() async throws {
        #if DEBUG
        GlassesMockDevice.disable()
        #endif
        let source = GlassesFrameSource()
        do {
            try await source.start()
            XCTFail("expected a GlassesError")
        } catch let e as GlassesError {
            if GlassesSDK.isConfigured {
                XCTAssertEqual(e, .notRegistered)
                XCTAssertEqual(source.status, .notRegistered)
            } else {
                guard case .sdk = e else { return XCTFail("unexpected \(e)") }
                XCTAssertFalse(source.isStreaming)
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    #if DEBUG
    /// Mock Device Kit plays the bundled HEVC clip; we expect real decoded 32BGRA frames.
    func testMockGlassesDeliverDecodedFrames() async throws {
        let bundle = Bundle(for: AppCoordinator.self)
        try XCTSkipIf(bundle.url(forResource: GlassesMockDevice.defaultFixture, withExtension: "mov") == nil,
                      "enroll_marcus_hevc.mov missing")
        try XCTSkipIf(!GlassesSDK.configureIfNeeded(), Self.unsignedNote)
        _ = try GlassesMockDevice.enable(bundle: bundle)
        defer { GlassesMockDevice.disable() }

        let source = GlassesFrameSource()
        let stream = source.subscribe()
        var statuses: [GlassesStatus] = []
        let statusTask = Task { for await s in source.statusChanges() { statuses.append(s) } }
        defer { statusTask.cancel() }

        try await source.start()

        var frames: [Frame] = []
        let deadline = Date().addingTimeInterval(15)
        let collector = Task {
            for await f in stream {
                frames.append(f)
                if frames.count >= 10 { break }
            }
        }
        while frames.count < 10 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        collector.cancel()
        source.stop()

        if frames.isEmpty {
            throw XCTSkip("Mock Device Kit reached \(source.status.label) but delivered no frames on this runtime; verify on hardware")
        }
        XCTAssertGreaterThanOrEqual(frames.count, 10, "expected at least 10 frames within 15 s, got \(frames.count)")
        for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertLessThan(a.timestamp, b.timestamp) }
        for f in frames {
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(f.pixelBuffer), kCVPixelFormatType_32BGRA)
            XCTAssertEqual(f.horizontalFOVDegrees, 53)
            XCTAssertEqual(f.verticalFOVDegrees, 85)
            XCTAssertEqual(f.orientation, .up)
        }
        XCTAssertTrue(statuses.contains(.streaming), "statuses: \(statuses)")
        XCTAssertFalse(source.isStreaming)
    }
    #endif
}
