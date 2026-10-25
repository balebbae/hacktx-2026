import ImageIO
import Foundation

/// Where the glasses camera is in its lifecycle. Mirrors the Meta DAT states but
/// in words the UI and the audio engine (S3/S5) can act on.
enum GlassesStatus: Equatable, Sendable {
    case idle
    case notRegistered
    case cameraPermissionDenied
    case connecting
    case waitingForFrames
    case streaming
    case paused
    case stopped(reason: String)
    case failed(reason: String)

    var label: String {
        switch self {
        case .idle: return "Not started"
        case .notRegistered: return "Glasses not connected"
        case .cameraPermissionDenied: return "Camera permission denied"
        case .connecting: return "Connecting to glasses"
        case .waitingForFrames: return "Waiting for frames"
        case .streaming: return "Streaming"
        case .paused: return "Paused"
        case .stopped(let reason): return "Stopped: \(reason)"
        case .failed(let reason): return "Error: \(reason)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connecting, .waitingForFrames, .streaming, .paused: return true
        default: return false
        }
    }
}

/// Bridged by S5 into `AudioEngineController` (S3): while the glasses camera streams,
/// the glasses hold Bluetooth Classic for video, so TTS must ride A2DP and the
/// phone mic must be used for speech. When `isStreaming` flips, the audio route is re-evaluated.
protocol GlassesStreamCoordinator: AnyObject {
    /// True from the first decoded frame until the stream stops or fails.
    var isStreaming: Bool { get }
    var status: GlassesStatus { get }
    /// Decoded frames per second over the last second (0 while not streaming).
    var framesPerSecond: Double { get }
    func streamingChanges() -> AsyncStream<Bool>
    func statusChanges() -> AsyncStream<GlassesStatus>
}

enum GlassesError: LocalizedError, Equatable {
    case notRegistered
    case cameraPermissionDenied
    case noDevice
    case sdk(String)

    var errorDescription: String? {
        switch self {
        case .notRegistered: return "Connect the glasses first (Meta AI app, Developer Mode on)."
        case .cameraPermissionDenied: return "Camera permission for the glasses was denied."
        case .noDevice: return "No glasses are connected."
        case .sdk(let message): return message
        }
    }
}

/// Ray-Ban Meta Gen 2 camera: 12 MP, 3:4 portrait stream. These are the values the
/// perception module uses for bearing; `docs/CALIBRATION.md` records measurements.
enum GlassesCameraGeometry {
    static let horizontalFOVDegrees: Double = 53
    static let verticalFOVDegrees: Double = 85
    static let orientation: CGImagePropertyOrientation = .up
}
