import Foundation

/// A hazard as any detector sees it: what it would be announced as, where (clock position) and how far, when known.
struct HazardSighting: Equatable {
    let kind: String
    let clock: Int
    let meters: Double?

    /// On-device Vision says "stairs"; the vision model says "stairs down", "step", "staircase". One word per thing,
    /// so both detectors land on the same registry entry.
    static func kind(_ name: String) -> String {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if n.contains("stair") || n.contains("step") { return "stairs" }
        if n.contains("escalator") { return "escalator" }
        if n.contains("crosswalk") || n.contains("crossing") { return "crosswalk" }
        return n
    }

    /// Things in the walking path are one kind whatever the model calls them (wall, couch, laptop): the on-device
    /// looming detector cannot name them, and the same wall is the same obstacle under every name.
    static let obstacle = "obstacle"

    var key: String { "\(kind)@\(clock)" }
}

/// One hazard is one hazard. On-device Vision ("Stairs ahead.") and the vision model ("Stairs down, 12 o'clock,
/// 3 meters.") see the same thing seconds apart, with different words, dedupe keys and cooldown tables, so both
/// alerts used to play. Every hazard and path alert now passes through here, keyed by kind + clock position:
/// - the same key again within `window` is the other detector's view of the same thing: dropped;
/// - within `repeatAfter` it is said again only when it is news: the wearer closed in by `approachMeters`, it
///   became close, or it is `newObstacleMeters` farther (another thing behind the first).
/// A different kind or clock position is always a different hazard. Pure with respect to `now`.
struct HazardRegistry {
    struct Entry: Equatable { let sighting: HazardSighting; let at: TimeInterval }

    var window: TimeInterval = 2.5
    var repeatAfter: TimeInterval = 8
    var approachMeters = 1.0
    var closeMeters = 1.5
    var newObstacleMeters = 2.0
    private(set) var entries: [String: Entry] = [:]

    init() {}

    /// True when the sighting should be spoken; the registry then remembers it.
    mutating func admit(_ s: HazardSighting, now: TimeInterval) -> Bool {
        entries = entries.filter { now - $0.value.at <= max(window, repeatAfter) }
        if let e = entries[s.key] {
            let since = now - e.at
            if since < window { return false }
            if since < repeatAfter, !Self.isNews(s, after: e.sighting, approach: approachMeters, close: closeMeters, farther: newObstacleMeters) { return false }
        }
        entries[s.key] = Entry(sighting: s, at: now)
        return true
    }

    /// Nearer by a clear margin, newly close, or far enough behind to be another thing. A sighting without a
    /// distance says nothing new; the first distance for a thing announced without one is worth a word only when it
    /// is close (the on-device "Obstacle ahead." was the alert; "Wall ahead, close." is the follow-up that matters).
    static func isNews(_ s: HazardSighting, after last: HazardSighting, approach: Double, close: Double, farther: Double) -> Bool {
        guard let m = s.meters else { return false }
        guard let was = last.meters else { return m < close }
        return m <= was - approach || (m < close && was >= close) || m > was + farther
    }
}
