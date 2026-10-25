import Foundation
import CoreMotion
import QuartzCore
import os

/// Is the wearer walking? Wall and hazard alerts only matter then; standing still (talking, sitting at a table)
/// they are noise. Two signals, either is enough: the phone's own motion (it rides in a pocket or hand; no
/// permission needed for raw device motion) and the camera view steadily expanding forward (`noteExpansion`).
/// Every switch to "walking" is logged with its cause, so a device log shows why an alert played.
final class MotionState: @unchecked Sendable {
    /// RMS of user acceleration (g) over `window` above which the phone counts as walking. Walking with the phone in a
    /// pocket or hand reads 0.15–0.4 g; holding it while talking 0.02–0.1 g.
    var walkingRMS = 0.15
    /// Mean signed inverse time-to-contact (1/s) of the centre of view above which the wearer moves toward something…
    var expansionRate = 0.3
    /// …with at least this share of the samples expanding (a nod or someone leaning in is one or two samples).
    var expansionShare = 0.75
    var window: TimeInterval = 2
    /// Stays "moving" this long after the last moving sample, so a pause in stride does not drop alerts.
    var hold: TimeInterval = 1.5
    var log: (String) -> Void = { DiagnosticLog.write($0) }

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
        let started: String? = state.withLock { s in
            s.accel.append((t, g))
            s.accel.removeAll { $0.t < t - window }
            guard s.accel.count >= 10 else { return nil }
            let rms = (s.accel.reduce(0) { $0 + $1.g * $1.g } / Double(s.accel.count)).squareRoot()
            guard rms > walkingRMS else { return nil }
            return Self.extend(&s, t + hold, now: t) ? String(format: "motion: walking (phone %.2f g)", rms) : nil
        }
        if let started { log(started) }
    }

    /// Signed inverse time-to-contact of the centre of view (1/s, negative = receding), from `SceneAwareness` at ~4 Hz.
    func noteExpansion(_ rate: Double, at t: TimeInterval) {
        let started: String? = state.withLock { s in
            s.expansion.append((t, rate))
            s.expansion.removeAll { $0.t < t - window }
            guard s.expansion.count >= 6 else { return nil }
            let mean = s.expansion.reduce(0, { $0 + $1.rate }) / Double(s.expansion.count)
            let share = Double(s.expansion.filter { $0.rate > 0 }.count) / Double(s.expansion.count)
            guard mean > expansionRate, share >= expansionShare else { return nil }
            return Self.extend(&s, t + hold, now: t) ? String(format: "motion: walking (view expanding %.2f/s)", mean) : nil
        }
        if let started { log(started) }
    }

    func isMoving(at t: TimeInterval = CACurrentMediaTime()) -> Bool { state.withLock { t <= $0.movingUntil } }

    /// Extends the moving window; true when the wearer was still before.
    private static func extend(_ s: inout State, _ until: TimeInterval, now: TimeInterval) -> Bool {
        let wasStill = now > s.movingUntil
        s.movingUntil = max(s.movingUntil, until)
        return wasStill
    }
}
