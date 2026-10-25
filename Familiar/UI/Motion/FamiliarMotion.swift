import SwiftUI

/// The motion vocabulary every piece of the library shares (docs/DESIGN_SPEC.md §8): one spring for small, Mimo-like
/// moves, one ease for diffusion, one short ease for tap feedback. Motion expresses state and never demands attention.
enum FamiliarMotion {
    /// Small moves: a pill sliding, a toast rising, a digit flipping.
    static let spring: Animation = .spring(response: 0.44, dampingFraction: 0.78)
    /// Background diffusion: glass fading in, a skeleton resolving into content.
    static let diffusion: Animation = .easeInOut(duration: 0.35)
    /// Tap feedback: 0.97 scale for 100 ms.
    static let tap: Animation = .easeOut(duration: 0.1)
    /// Something settling after a nudge (menu closing, tilt returning).
    static let settle: Animation = .spring(response: 0.5, dampingFraction: 0.86)

    /// Stagger between sibling elements (digits, menu items, particles).
    static let stagger: Double = 0.045

    /// `true` when the view may move. `false` under the vision profile's `simplifyMotion` or the system Reduce Motion.
    static func animates(_ scale: VisionScale, reduceMotion: Bool) -> Bool {
        !(scale.simplifyMotion || reduceMotion)
    }

    /// The spring when motion is allowed, a short crossfade otherwise.
    static func reduced(_ animates: Bool) -> Animation {
        animates ? spring : .easeInOut(duration: 0.15)
    }
}

/// Deterministic pseudo-random numbers for Canvas drawings (particles, goo jitter). Never `Double.random` in a body,
/// so previews and `ImageRenderer` snapshots are stable.
enum MotionNoise {
    /// A value in 0..<1 derived from `seed` and `index`.
    static func unit(_ seed: Int, _ index: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 1_000_003 &+ index &* 7_919 &+ 12_345)
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x = x &* 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 1_000_000) / 1_000_000
    }
}
