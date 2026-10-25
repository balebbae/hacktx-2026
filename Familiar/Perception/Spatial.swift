import Foundation
import CoreGraphics

/// Bearing and distance geometry. Pure functions so the thresholds can be calibrated from `docs/CALIBRATION.md`.
struct SpatialConfig: Equatable {
    /// Metres. `close` below `closeMax`, `medium` up to `mediumMax`, `far` beyond.
    var closeMaxMeters: Double = 1.5
    var mediumMaxMeters: Double = 3.0
    /// Assumed physical height of a detected face box (chin to brow), metres.
    var faceHeightMeters: Double = 0.20
    static let `default` = SpatialConfig()
}

enum Spatial {
    /// Horizontal angle of a normalized frame x (0 = left edge, 1 = right edge). Positive = right.
    static func bearingDegrees(centerX: Double, hFOV: Double) -> Double {
        let half = hFOV * .pi / 360
        return atan((centerX - 0.5) * 2 * tan(half)) * 180 / .pi
    }

    /// Band by frame fraction: centre 25 % ahead, next 25 % left / right, outer 12.5 % far left / far right.
    static func band(centerX: Double) -> BearingBand {
        switch centerX {
        case ..<0.125: return .farLeft
        case ..<0.375: return .left
        case ..<0.625: return .ahead
        case ..<0.875: return .right
        default: return .farRight
        }
    }

    static func bearing(centerX: Double, hFOV: Double) -> Bearing {
        Bearing(degrees: bearingDegrees(centerX: centerX, hFOV: hFOV), band: band(centerX: centerX))
    }

    /// Pinhole estimate: a face of `faceHeightMeters` subtending `(h / H) * vFOV` degrees.
    static func distanceMeters(faceHeightPx: Double, frameHeightPx: Double, vFOV: Double, config: SpatialConfig = .default) -> Double {
        guard faceHeightPx > 0, frameHeightPx > 0 else { return .infinity }
        let angle = (faceHeightPx / frameHeightPx) * vFOV * .pi / 180
        return config.faceHeightMeters / (2 * tan(angle / 2))
    }

    static func distance(meters: Double, config: SpatialConfig = .default) -> Distance {
        if meters < config.closeMaxMeters { return .close }
        if meters <= config.mediumMaxMeters { return .medium }
        return .far
    }

    static func distance(faceHeightPx: Double, frameHeightPx: Double, vFOV: Double, config: SpatialConfig = .default) -> Distance {
        distance(meters: distanceMeters(faceHeightPx: faceHeightPx, frameHeightPx: frameHeightPx, vFOV: vFOV, config: config), config: config)
    }
}
