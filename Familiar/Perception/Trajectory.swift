import Foundation

struct TrajectoryConfig: Equatable {
    /// Look-back for the growth test, seconds.
    var window: TimeInterval = 1.5
    var minObservations = 3
    /// Box height growth over `window` that counts as approaching (0.25 = +25 %).
    var growth: Double = 0.25
    /// Time the track must stay `close` before `arrived`.
    var arriveStable: TimeInterval = 1.0
    /// Confirmed track unseen this long -> lost (-> `knownLeft`).
    var lostAfter: TimeInterval = 2.5
    static let `default` = TrajectoryConfig()
}

struct TrackObservation: Equatable {
    let t: TimeInterval
    let heightPx: Double
    let distance: Distance
}

enum TrajectoryVerdict: Equatable { case approaching, arrived }

/// Per-track episode state. An approach episode ends when the person gets farther again; an arrival episode ends
/// when they leave `close`. Each verdict fires once per episode.
struct TrajectoryState: Equatable {
    var approachAnnounced = false
    var arrivedAnnounced = false
    var closeSince: TimeInterval?
    var farthestRecent: Distance?
}

enum Trajectory {
    static func rank(_ d: Distance) -> Int { switch d { case .close: return 0; case .medium: return 1; case .far: return 2 } }

    /// Feed the full history (oldest first, already trimmed by the tracker) and the mutable episode state.
    static func evaluate(history: [TrackObservation], state: inout TrajectoryState, config: TrajectoryConfig = .default) -> [TrajectoryVerdict] {
        guard let last = history.last else { return [] }
        var out: [TrajectoryVerdict] = []
        let recent = history.filter { $0.t >= last.t - config.window }

        // Reset the approach episode when the person moved away (bin increased vs. the start of the window).
        if let first = recent.first, rank(last.distance) > rank(first.distance) {
            state.approachAnnounced = false
        }

        if recent.count >= config.minObservations, let first = recent.first {
            let binDecreased = rank(last.distance) < rank(first.distance)
            let grew = first.heightPx > 0 && (last.heightPx / first.heightPx - 1) >= config.growth
            if (binDecreased || grew), !state.approachAnnounced, last.distance != .far {
                state.approachAnnounced = true
                out.append(.approaching)
            }
        }

        if last.distance == .close {
            if state.closeSince == nil { state.closeSince = last.t }
            if let since = state.closeSince, last.t - since >= config.arriveStable, !state.arrivedAnnounced {
                state.arrivedAnnounced = true
                out.append(.arrived)
            }
        } else {
            state.closeSince = nil
            state.arrivedAnnounced = false
        }
        return out
    }
}
