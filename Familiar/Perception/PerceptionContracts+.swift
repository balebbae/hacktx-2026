import Foundation
import CoreGraphics
import CoreVideo

// Perception-only types. Nothing here changes a Core contract.

/// Five ArcFace alignment points in full-resolution upright pixel coordinates (top-left origin):
/// image-left eye, image-right eye, nose tip, image-left mouth corner, image-right mouth corner.
struct FaceLandmarks5: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var nose: CGPoint
    var mouthLeft: CGPoint
    var mouthRight: CGPoint
    var points: [CGPoint] { [leftEye, rightEye, nose, mouthLeft, mouthRight] }
}

/// One detected face in one frame. Box is normalized with a top-left origin in the *upright* image.
struct FaceDetection: Equatable {
    var box: CGRect
    var confidence: Float
    var yawDegrees: Double?
    var rollDegrees: Double?
    var pitchDegrees: Double?
    var landmarks: FaceLandmarks5?
    /// Inner-lip vertical gap divided by face height (nil without landmarks).
    var mouthOpenness: Double?
}

/// Output of one detector pass: detections plus the upright pixel size they are normalized against.
struct DetectionResult {
    var detections: [FaceDetection]
    var uprightSize: CGSize
    var timestamp: TimeInterval
}

/// `FaceEmbedding` plus the pose it was taken at, so the tracker can keep a yaw-diverse top-8.
struct ScoredEmbedding: Equatable {
    var embedding: FaceEmbedding
    var yawDegrees: Double
}

extension TrackSnapshot {
    /// Copy with a different identity (snapshots are immutable value types).
    func relabeled(_ identity: Identity) -> TrackSnapshot {
        TrackSnapshot(trackID: trackID, identity: identity, bearing: bearing, distance: distance, faceBox: faceBox, faceHeightPx: faceHeightPx,
                      yawDegrees: yawDegrees, isFacingUser: isFacingUser, mouthOpenness: mouthOpenness, quality: quality, timestamp: timestamp)
    }
}

/// Deterministic embedder for tests and the Simulator. Every call returns the unit vector for `label`
/// (optionally decided per buffer by `labeler`), so a gallery built with `FakeEmbedder.vector(for:)` matches.
final class FakeEmbedder: EmbeddingProvider, @unchecked Sendable {
    let modelID: String
    let dimension: Int
    var label: String
    /// Optional per-call override, e.g. decide the label from the frame being embedded.
    var labeler: ((CVPixelBuffer) -> String)?
    /// Simulated inference time, seconds.
    var latency: TimeInterval = 0
    private(set) var calls = 0

    init(label: String = "person", modelID: String = "fake", dimension: Int = 512) {
        self.label = label; self.modelID = modelID; self.dimension = dimension
    }

    static func vector(for label: String, dimension: Int = 512) -> [Float] {
        ScriptedPerception.unitVector(seed: label, dimension: dimension)
    }

    func embed(_ alignedFace112: CVPixelBuffer) async throws -> [Float] {
        calls += 1
        if latency > 0 { try? await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000)) }
        return Self.vector(for: labeler?(alignedFace112) ?? label, dimension: dimension)
    }
}

/// Tries `primary`, falls back to `fallback` on error (e.g. on-device ORT → Modal, or the reverse).
final class FallbackEmbedder: EmbeddingProvider, @unchecked Sendable {
    let primary: EmbeddingProvider
    let fallback: EmbeddingProvider
    var modelID: String { primary.modelID }
    var dimension: Int { primary.dimension }
    private(set) var fallbackCount = 0

    init(primary: EmbeddingProvider, fallback: EmbeddingProvider) { self.primary = primary; self.fallback = fallback }

    func embed(_ alignedFace112: CVPixelBuffer) async throws -> [Float] {
        do { return try await primary.embed(alignedFace112) }
        catch {
            fallbackCount += 1
            return try await fallback.embed(alignedFace112)
        }
    }
}
