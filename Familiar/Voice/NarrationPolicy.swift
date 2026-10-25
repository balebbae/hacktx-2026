import Foundation

/// Decides what, if anything, to say about a new vision reading. Pure with respect to `now`.
///
///   Alerts only while the wearer walks: standing still (talking, at a table) the couch and the laptop are noise.
///   path      blocked/caution within `alertMeters` (4 m) → priority 0 at once ("Wall ahead, 2 meters."). The
///             distance is aged by `walkSpeed` × the reading's age (at most `maxAging`). One alert per obstacle
///             episode, repeated only while the wearer closes in (at least `approachMeters` nearer, `pathRepeat`
///             apart, and once more when it gets close). The model renames the same thing from reading to reading
///             (couch, sofa, chair, bean bag), so a new name is not a new obstacle; an obstacle `newObstacleMeters`
///             farther than the last alert is, and the episode re-arms after `rearmClear` seconds of clear path.
///             Quiet mode or face to face with someone: only obstacles that are close, and never the person.
///   hazards   within `hazardMeters` → priority 0, once per kind per `hazardCooldown`, any two `hazardGap` apart.
///   gist      the model's one-line summary, chatty mode only (normal mode answers "Poyo, what's around me?"
///             instead), only when the scene changed, at most every `gistChatty` s, never face to face with someone,
///             never a near-repeat of the last three lines.
struct NarrationPolicy {
    struct Config {
        /// Generous on purpose: a reading is about 2.5 s old when it arrives, and the wearer may be walking.
        var alertMeters = 4.0
        var hazardMeters = 4.0
        var closeMeters = 1.5
        var pathRepeat: TimeInterval = 5
        /// m/s: a slow walk with a cane, used to age a reading's distances.
        var walkSpeed = 0.7
        var maxAging = 1.0
        var approachMeters = 1.0
        var newObstacleMeters = 2.0
        var rearmClear: TimeInterval = 5
        var hazardCooldown: TimeInterval = 60
        var hazardGap: TimeInterval = 10
        var gistChatty: TimeInterval = 8
        var gistChange = 0.5
    }

    var config = Config()
    private var lastPathAlert: TimeInterval?
    private var lastAlertMeters = Double.infinity
    private var clearSince: TimeInterval?
    private var hazardSpoken: [String: TimeInterval] = [:]
    private var lastHazardAt: TimeInterval = -.infinity
    private var lastGistAt: TimeInterval?
    private var lastGistPlace: String?
    private var lastGistObjects: Set<String> = []
    private var recent: [String] = []

    /// What to say, and for alerts the hazard it is about, so `HazardRegistry` can match it against the other detector.
    struct Narration: Equatable { let utterance: Utterance; let hazard: HazardSighting? }

    init(config: Config = Config()) { self.config = config }

    mutating func utterances(for r: SceneReading, mode: ChatterMode, now: TimeInterval, inConversation: Bool, moving: Bool = true) -> [Utterance] {
        decide(for: r, mode: mode, now: now, inConversation: inConversation, moving: moving).map(\.utterance)
    }

    mutating func decide(for r: SceneReading, mode: ChatterMode, now: TimeInterval, inConversation: Bool, moving: Bool = true) -> [Narration] {
        if moving, let n = pathAlert(r, now: now, closeOnly: mode == .quiet || inConversation, inConversation: inConversation) { return [n] }
        if moving, let n = hazard(r, now: now) { return [n] }
        // Standing in a crowd the room changes every second and none of it is news; "Poyo, what's around me?" answers.
        if mode == .chatty, let u = gist(r, now: now, inConversation: inConversation) { return [Narration(utterance: u, hazard: nil)] }
        return []
    }

    private mutating func pathAlert(_ r: SceneReading, now: TimeInterval, closeOnly: Bool, inConversation: Bool) -> Narration? {
        let reported = r.pathMeters ?? (r.path == .blocked ? config.alertMeters : nil)
        guard r.path != .clear, let reported, reported <= config.alertMeters else {
            if clearSince == nil { clearSince = now }
            if let since = clearSince, now - since >= config.rearmClear { lastPathAlert = nil; lastAlertMeters = .infinity }
            return nil
        }
        clearSince = nil
        let m = max(0, reported - min(config.maxAging, config.walkSpeed * max(0, now - r.at)))
        // The person in front of you is who you are talking to; people get their own cues.
        if inConversation, let what = r.pathWhat?.lowercased(), what.contains("person") || what.contains("people") { return nil }
        if closeOnly, m >= config.closeMeters { return nil }
        // Farther than the last alert by a clear margin (the laptop, then the wall behind it): a new obstacle.
        if m > lastAlertMeters + config.newObstacleMeters { lastPathAlert = nil; lastAlertMeters = .infinity }
        if let last = lastPathAlert {
            let closer = m <= lastAlertMeters - config.approachMeters
            let nowClose = m < config.closeMeters && lastAlertMeters >= config.closeMeters
            guard now - last >= config.pathRepeat, closer || nowClose else { return nil }
        }
        lastPathAlert = now
        lastAlertMeters = m
        let bearing = r.bearing(r.pathX)
        return Narration(utterance: Self.alert(Phrasebook.pathAlert(what: r.pathWhat, bearing: bearing, meters: r.pathMeters.map { _ in m }), key: "path"),
                         hazard: HazardSighting(kind: HazardSighting.obstacle, clock: bearing.clock, meters: r.pathMeters.map { _ in m }))
    }

    private mutating func hazard(_ r: SceneReading, now: TimeInterval) -> Narration? {
        guard now - lastHazardAt >= config.hazardGap else { return nil }
        for h in r.hazards where (h.meters ?? 0) <= config.hazardMeters {
            let key = h.name.lowercased()
            if let last = hazardSpoken[key], now - last < config.hazardCooldown { continue }
            let bearing = r.bearing(h.x)
            guard let text = SpeechSanitizer.clean(Phrasebook.sceneHazard(h.name, bearing: bearing, meters: h.meters)) else { continue }
            hazardSpoken[key] = now
            lastHazardAt = now
            return Narration(utterance: Self.alert(text, key: "hazard:\(key)"), hazard: HazardSighting(kind: HazardSighting.kind(h.name), clock: bearing.clock, meters: h.meters))
        }
        return nil
    }

    private mutating func gist(_ r: SceneReading, now: TimeInterval, inConversation: Bool) -> Utterance? {
        guard !inConversation else { return nil }
        if let last = lastGistAt, now - last < config.gistChatty { return nil }
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
