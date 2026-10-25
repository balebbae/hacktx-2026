import Foundation

/// Decides what, if anything, to say about a new vision reading. Pure with respect to `now`.
///
///   Alerts only while the wearer walks: standing still (talking, at a table) the couch and the laptop are noise.
///   path      blocked/caution within `alertMeters` (4 m) → priority 0 at once ("Wall ahead, 2 meters."). The
///             distance is aged by `walkSpeed` × the reading's age. Repeats while the wearer closes in (at least
///             `approachMeters` nearer, `pathRepeat` apart, and once more when it gets close); a different or farther
///             obstacle starts over; re-arms after `rearmClear` seconds of clear path.
///   hazards   within `hazardMeters` → priority 0, once per kind per `hazardCooldown`; at most one per reading.
///   gist      the model's one-line summary, priority 2, only while walking (chatty: also standing), only when the
///             scene changed (new place or a different set of objects), at most every 20 s (normal) / 8 s (chatty),
///             never in quiet mode, never face to face with someone, never a near-repeat of the last three lines.
struct NarrationPolicy {
    struct Config {
        /// Generous on purpose: a reading is about 2.5 s old when it arrives, and the wearer may be walking.
        var alertMeters = 4.0
        var hazardMeters = 4.0
        var pathRepeat: TimeInterval = 3
        /// m/s: a slow walk with a cane, used to age a reading's distances.
        var walkSpeed = 0.7
        var approachMeters = 1.0
        var rearmClear: TimeInterval = 3
        var hazardCooldown: TimeInterval = 10
        var gistNormal: TimeInterval = 20
        var gistChatty: TimeInterval = 8
        var gistChange = 0.5
    }

    var config = Config()
    private var lastPathAlert: TimeInterval?
    private var lastAlertMeters = Double.infinity
    private var lastAlertWhat: String?
    private var clearSince: TimeInterval?
    private var hazardSpoken: [String: TimeInterval] = [:]
    private var lastGistAt: TimeInterval?
    private var lastGistPlace: String?
    private var lastGistObjects: Set<String> = []
    private var recent: [String] = []

    init(config: Config = Config()) { self.config = config }

    mutating func utterances(for r: SceneReading, mode: ChatterMode, now: TimeInterval, inConversation: Bool, moving: Bool = true) -> [Utterance] {
        if moving, let u = pathAlert(r, now: now) { return [u] }
        if moving, let u = hazard(r, now: now) { return [u] }
        // Scene updates while walking (chatty: standing too). Standing in a crowd, the room changes every second
        // and none of it is news; "Poyo, what's around me?" still answers.
        if moving || mode == .chatty, let u = gist(r, mode: mode, now: now, inConversation: inConversation) { return [u] }
        return []
    }

    private mutating func pathAlert(_ r: SceneReading, now: TimeInterval) -> Utterance? {
        let reported = r.pathMeters ?? (r.path == .blocked ? config.alertMeters : nil)
        guard r.path != .clear, let reported, reported <= config.alertMeters else {
            if clearSince == nil { clearSince = now }
            if let since = clearSince, now - since >= config.rearmClear { lastPathAlert = nil; lastAlertMeters = .infinity; lastAlertWhat = nil }
            return nil
        }
        clearSince = nil
        let m = max(0, reported - config.walkSpeed * max(0, now - r.at))
        let what = r.pathWhat?.lowercased()
        // A different thing, or one farther than the last alert (the laptop then the wall behind it): a new obstacle.
        if (what != nil && lastAlertWhat != nil && what != lastAlertWhat) || m > lastAlertMeters + config.approachMeters {
            lastPathAlert = nil; lastAlertMeters = .infinity
        }
        if let last = lastPathAlert {
            let closer = m <= lastAlertMeters - config.approachMeters
            let nowClose = m < 1.5 && lastAlertMeters >= 1.5
            guard now - last >= config.pathRepeat, closer || nowClose else { return nil }
        }
        lastPathAlert = now
        lastAlertMeters = m
        lastAlertWhat = what ?? lastAlertWhat
        return Self.alert(Phrasebook.pathAlert(what: r.pathWhat, bearing: r.bearing(r.pathX), meters: r.pathMeters.map { _ in m }), key: "path")
    }

    private mutating func hazard(_ r: SceneReading, now: TimeInterval) -> Utterance? {
        for h in r.hazards where (h.meters ?? 0) <= config.hazardMeters {
            let key = h.name.lowercased()
            if let last = hazardSpoken[key], now - last < config.hazardCooldown { continue }
            guard let text = SpeechSanitizer.clean(Phrasebook.sceneHazard(h.name, bearing: r.bearing(h.x), meters: h.meters)) else { continue }
            hazardSpoken[key] = now
            return Self.alert(text, key: "hazard:\(key)")
        }
        return nil
    }

    private mutating func gist(_ r: SceneReading, mode: ChatterMode, now: TimeInterval, inConversation: Bool) -> Utterance? {
        guard mode != .quiet, !inConversation else { return nil }
        if let last = lastGistAt, now - last < (mode == .chatty ? config.gistChatty : config.gistNormal) { return nil }
        let objects = Set(r.objects.map { $0.name.lowercased() })
        let changed = lastGistAt == nil || r.place?.lowercased() != lastGistPlace || Self.jaccardDistance(objects, lastGistObjects) >= config.gistChange
        guard changed, let text = SpeechSanitizer.clean(r.summary, maxWords: 14) else { return nil }
        guard !recent.contains(where: { Self.similar($0, text) }) else { return nil }
        lastGistAt = now
        lastGistPlace = r.place?.lowercased()
        lastGistObjects = objects
        recent = Array((recent + [text]).suffix(3))
        return Utterance(text: text, priority: 2, category: "gist", personID: nil, dedupeKey: "gist", audience: .user, earcon: false)
    }

    private static func alert(_ text: String, key: String) -> Utterance {
        Utterance(text: text, priority: 0, category: "hazard", personID: nil, dedupeKey: key, audience: .user, earcon: true)
    }

    static func jaccardDistance(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        return union.isEmpty ? 0 : 1 - Double(a.intersection(b).count) / Double(union.count)
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> Set<String> { Set(CommandParser.normalize(s).split(separator: " ").map(String.init)) }
        return jaccardDistance(words(a), words(b)) <= 0.4
    }
}
