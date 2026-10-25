import Foundation
import AVFoundation
import CoreVideo
import QuartzCore

/// Plays an .mp4/.mov from the bundle (Resources/Fixtures) or any URL through AVAssetReader with real-time pacing,
/// loops forever, and emits 32BGRA `Frame`s stamped on the host clock. Timestamps = start + pts.
final class VideoFileFrameSource: FrameSource, @unchecked Sendable {
    let url: URL
    let horizontalFOVDegrees: Double
    let verticalFOVDegrees: Double
    var loops = true
    /// Playback rate multiplier (tests can speed up).
    var rate: Double = 1.0

    private let bus = EventBus<Frame>(defaultPolicy: .bufferingNewest(1))
    private var task: Task<Void, Never>?
    private(set) var frameCount = 0

    init(url: URL, horizontalFOVDegrees: Double = 53, verticalFOVDegrees: Double = 85) {
        self.url = url
        self.horizontalFOVDegrees = horizontalFOVDegrees
        self.verticalFOVDegrees = verticalFOVDegrees
    }

    /// Looks up `<name>.mp4` / `.mov` in the main bundle and applies the FOV from fixtures.json when present.
    convenience init?(fixtureNamed name: String, bundle: Bundle = .main) {
        let base = (name as NSString).deletingPathExtension
        let url = ["mp4", "mov", "MOV", "m4v"].lazy.compactMap { bundle.url(forResource: base, withExtension: $0) }.first
        guard let url else { return nil }
        let fov = FixtureManifest.load(from: bundle)?.fov
        self.init(url: url, horizontalFOVDegrees: fov?.horizontalDegrees ?? 53, verticalFOVDegrees: fov?.verticalDegrees ?? 85)
    }

    static func availableFixtures(bundle: Bundle = .main) -> [String] {
        let urls = (bundle.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? []) + (bundle.urls(forResourcesWithExtension: "mov", subdirectory: nil) ?? [])
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    func subscribe() -> AsyncStream<Frame> { bus.subscribe() }

    func start() async throws {
        guard task == nil else { return }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFileFrameSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track in \(url.lastPathComponent)"])
        }
        let transform = try await track.load(.preferredTransform)
        let orientation = Self.orientation(for: transform)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            repeat {
                do { try await self.playOnce(asset: asset, track: track, orientation: orientation) } catch { NSLog("[VideoFileFrameSource] %@: %@", self.url.lastPathComponent, "\(error)"); break }
            } while self.loops && !Task.isCancelled
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func playOnce(asset: AVURLAsset, track: AVAssetTrack, orientation: CGImagePropertyOrientation) async throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "VideoFileFrameSource", code: 2) }
        let start = CACurrentMediaTime()
        while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            let target = start + pts / rate
            let wait = target - CACurrentMediaTime()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            frameCount += 1
            bus.publish(Frame(pixelBuffer: pb, timestamp: target, orientation: orientation,
                              horizontalFOVDegrees: horizontalFOVDegrees, verticalFOVDegrees: verticalFOVDegrees))
        }
        reader.cancelReading()
    }

    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
