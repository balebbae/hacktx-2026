import Foundation
import CoreMotion
import QuartzCore
import os

/// Is the wearer walking? Wall and hazard alerts only matter then; standing still (talking, sitting at a table)
/// they are noise. Two signals, either is enough: the phone's own motion (it rides in a pocket or hand; no
/// permission needed for raw device motion) and the camera view expanding forward (`noteExpansion`).
final class MotionState: @unchecked Sendable {
    /// RMS of user acceleration (g) over `window` above which the phone counts as walking.
    var walkingRMS = 0.07
    /// Mean inverse time-to-contact (1/s) of the centre of view above which the wearer moves toward something.
    var expansionRate = 0.25
    var window: TimeInterval = 2
    /// Stays "moving" this long after the last moving sample, so a pause in stride does not drop alerts.
    var hold: TimeInterval = 1.5

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private struct State { var accel: [(t: TimeInterval, g: Double)] = []; var expansion: [(t: TimeInterval, rate: Double)] = []; var movingUntil: TimeInterval = -.infinity }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 25
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let a = motion?.userAcceleration else { return }
            self.noteAcceleration((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), at: CACurrentMediaTime())
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    func noteAcceleration(_ g: Double, at t: TimeInterval) {
        state.withLock { s in
            s.accel.append((t, g))
            s.accel.removeAll { $0.t < t - window }
            guard s.accel.count >= 10 else { return }
            let rms = (s.accel.reduce(0) { $0 + $1.g * $1.g } / Double(s.accel.count)).squareRoot()
            if rms > walkingRMS { s.movingUntil = max(s.movingUntil, t + hold) }
        }
    }

    /// Inverse time-to-contact of the centre of view (0 when nothing approaches), from `SceneAwareness` at ~4 Hz.
    func noteExpansion(_ rate: Double, at t: TimeInterval) {
        state.withLock { s in
            s.expansion.append((t, rate))
            s.expansion.removeAll { $0.t < t - window }
            guard s.expansion.count >= 4 else { return }
            if s.expansion.reduce(0, { $0 + $1.rate }) / Double(s.expansion.count) > expansionRate { s.movingUntil = max(s.movingUntil, t + hold) }
        }
    }

    func isMoving(at t: TimeInterval = CACurrentMediaTime()) -> Bool { state.withLock { t <= $0.movingUntil } }
}
