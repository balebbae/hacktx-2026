import Foundation
import CoreGraphics

/// One line of "audio description": what the closest person or group is doing. Motion and grouping only: never
/// looks, clothes or mood, and a name only when an agreed person's face sits inside the body box.
enum ActionCaption: Equatable, Sendable {
    case crossing(name: String?, leftToRight: Bool, distance: Distance, fast: Bool)
    case walkingAway(hour: Int, distance: Distance)
    case group(count: Int, names: [String], hour: Int, distance: Distance, talking: Bool)

    var key: String {
        switch self {
        case .crossing: return "crossing"
        case .walkingAway: return "away"
        case .group: return "group"
        }
    }
    var distance: Distance {
        switch self { case let .crossing(_, _, d, _), let .walkingAway(_, d), let .group(_, _, _, d, _): return d }
    }
    var text: String { Phrasebook.action(self) }

    /// Whether and how to say a caption. Movie audio description fits between lines of dialogue, so routine captions
    /// wait for a pause (`inDialogueGap`). Someone crossing close while the wearer walks is a collision cue: priority 1,
    /// any mode, conversation or not. Groups are about people talking, so a conversation does not hold them back.
    static func utterance(for c: ActionCaption, mode: ChatterMode, moving: Bool, inConversation: Bool, inDialogueGap: Bool,
                          sinceLast: TimeInterval) -> Utterance? {
        if case .crossing(_, _, .close, _) = c, moving {
            return Utterance(text: c.text, priority: 1, category: "action", personID: nil, dedupeKey: "action:\(c.key)", audience: .user, earcon: true)
        }
        guard mode != .quiet, c.distance != .far || mode == .chatty, inDialogueGap else { return nil }
        guard sinceLast >= (mode == .chatty ? 8 : 20) else { return nil }
        if c.key != "group", inConversation { return nil }
        return Utterance(text: c.text, priority: 2, category: "action", personID: nil, dedupeKey: "action:\(c.key)", audience: .user, earcon: false)
    }
}

/// Pure decisions over on-device body boxes (Vision human rectangles, ≈4 Hz) and the face tracks perception keeps.
/// Emits at most one caption per pass: the closest of what qualifies.
///   crossing     a body moving sideways ≥ `crossSpeed` °/s, sustained over ≥ `crossWindow` s and ≥ `crossDegrees`;
///                bearings are corrected for head turns with the camera pan, and nothing is said while the head
///                turns faster than `maxPan`. "fast" when the lateral speed (angle × distance) is ≥ `fastMetersPerSecond`.
///   walkingAway  an unknown body shrinking ≥ `shrink` over `awayWindow` s (known people get "{Name} left.").
///   group        ≥ 2 people within `groupGapMeters` of each other side by side (angle × distance, so two people at
///                arm's length 1 m away count as much as two across the room) at similar distance, the nearest within
///                `groupMaxMeters`, talking (a member's mouth moving; speech nearby when no mouth is readable), held
///                `groupHold` s through detection flicker, not mostly facing the wearer (then the wearer is in that
///                conversation). Said once per group: again only when the agreed people in it change or it broke up.
struct ActionCaptioner {
    // shortcut: thresholds reasoned from walking speeds and the 53° view, not measured on glasses footage; calibrate on hardware.
    var bodyHeightMeters = 1.7
    var crossSpeed = 15.0
    var crossWindow: TimeInterval = 0.75
    var crossDegrees = 10.0
    var fastMetersPerSecond = 1.8
    var maxPan = 30.0
    var shrink = 0.25
    var awayWindow: TimeInterval = 1.5
    var groupGapMeters = 1.5
    var groupMaxMeters = 3.0
    var groupHold: TimeInterval = 3
    /// A face or body dropping out for a pass or two does not restart the hold.
    var groupFlicker: TimeInterval = 1.5
    /// Mouth-openness variance over `mouthWindow` above which a mouth is moving (`ActiveSpeakerConfig`, at 4 Hz).
    var mouthVariance = 0.0015
    var mouthWindow: TimeInterval = 2
    var mouthMinSamples = 5
    var groupForget: TimeInterval = 10
    var lostAfter: TimeInterval = 1
    var matchIoU = 0.2

    struct Person { let bearing: Double; let meters: Double; let name: String?; let facing: Bool?; var talking: Bool? = nil }

    private struct Obs { let t: TimeInterval; let world: Double; let height: Double; let pan: Double }
    private final class Track {
        let id: Int
        var box: CGRect
        var lastSeen: TimeInterval
        var history: [Obs] = []
        var crossed = false
        var away = false
        init(id: Int, box: CGRect, t: TimeInterval) { self.id = id; self.box = box; lastSeen = t }
    }

    private var tracks: [Track] = []
    private var nextID = 1
    /// Head yaw integrated from the camera pan, so `bearing + yaw` stays put for someone standing still.
    private var yaw = 0.0
    private var lastT: TimeInterval?
    private var groupCandidate: (signature: String, since: TimeInterval, last: TimeInterval)?
    private var mouths: [Int: [(t: TimeInterval, openness: Double)]] = [:]
    private var announcedGroup: String?
    private var groupLastSeen: TimeInterval = -.infinity
    private var recent: [(t: TimeInterval, text: String)] = []

    /// - bodies: normalized boxes, top-left origin. - faces: perception's tracks. - panRate: camera pan in °/s,
    /// positive when the head turns right. - speech: someone spoke in the last few seconds.
    mutating func update(bodies: [CGRect], faces: [TrackSnapshot], panRate: Double, speech: Bool, now: TimeInterval,
                         hFOV: Double, vFOV: Double) -> ActionCaption? {
        if let last = lastT { yaw += panRate * max(0, min(1, now - last)) }
        lastT = now
        match(bodies, now: now)
        noteMouths(faces, now: now)

        var candidates: [(caption: ActionCaption, meters: Double, track: Track?)] = []
        var people: [Person] = []
        for track in tracks where track.lastSeen == now {
            let b = track.box
            let bearing = Spatial.bearingDegrees(centerX: b.midX, hFOV: hFOV)
            let meters = distance(b, vFOV: vFOV)
            track.history.append(Obs(t: now, world: bearing + yaw, height: b.height, pan: panRate))
            track.history.removeAll { $0.t < now - 2 }
            let face = faces.first { b.contains(CGPoint(x: $0.faceBox.midX, y: $0.faceBox.midY)) }
            let name: String? = { if case let .known(_, n, _) = face?.identity { return n }; return nil }()
            people.append(Person(bearing: bearing, meters: meters, name: name, facing: face?.isFacingUser, talking: face.flatMap { mouthMoving($0) }))

            if !track.crossed, let c = crossing(track, name: name, meters: meters, now: now) {
                candidates.append((c, meters, track))
            }
            if !track.away, name == nil, !track.crossed, let c = walkingAway(track, bearing: bearing, meters: meters, now: now) {
                candidates.append((c, meters, track))
            }
        }
        // Seated people at a table often show a face but no full body: count those faces too.
        for f in faces where !tracks.contains(where: { $0.lastSeen == now && $0.box.contains(CGPoint(x: f.faceBox.midX, y: f.faceBox.midY)) }) {
            let name: String? = { if case let .known(_, n, _) = f.identity { return n }; return nil }()
            people.append(Person(bearing: f.bearing.degrees, meters: Self.meters(f.distance), name: name, facing: f.isFacingUser, talking: mouthMoving(f)))
        }
        let g = group(people, speech: speech, now: now)
        if let g { candidates.append((g.caption, g.meters, nil)) }

        guard let best = candidates.min(by: { $0.meters < $1.meters }) else { return nil }
        switch best.caption {
        case .crossing: best.track?.crossed = true
        case .walkingAway: best.track?.away = true
        case .group: announcedGroup = g?.signature
        }
        recent = recent.filter { $0.t > now - 10 } + [(now, best.caption.text)]
        return best.caption
    }

    /// Captions from the last 10 s, for the assistant's context line.
    func recentText(now: TimeInterval) -> String? {
        let lines = recent.filter { $0.t > now - 10 }.map(\.text)
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private mutating func match(_ boxes: [CGRect], now: TimeInterval) {
        var free = tracks.filter { now - $0.lastSeen <= lostAfter }
        for box in boxes {
            if let i = free.indices.max(by: { FaceTracker.iou(free[$0].box, box) < FaceTracker.iou(free[$1].box, box) }),
               FaceTracker.iou(free[i].box, box) >= matchIoU {
                free[i].box = box; free[i].lastSeen = now
                free.remove(at: i)
            } else {
                tracks.append(Track(id: nextID, box: box, t: now)); nextID += 1
            }
        }
        tracks.removeAll { now - $0.lastSeen > lostAfter }
    }

    /// Pinhole estimate from the box height; a box cut off by the frame edge is a person too close to fit.
    private func distance(_ b: CGRect, vFOV: Double) -> Double {
        if (b.minY < 0.02 || b.maxY > 0.98) && b.height > 0.5 { return 1 }
        let angle = Double(b.height) * vFOV * .pi / 180
        return angle > 0 ? bodyHeightMeters / (2 * tan(angle / 2)) : .infinity
    }

    private func crossing(_ track: Track, name: String?, meters: Double, now: TimeInterval) -> ActionCaption? {
        let window = track.history.filter { $0.t >= now - 1 }
        guard window.count >= 3, let first = window.first, let last = window.last, last.t - first.t >= crossWindow,
              window.allSatisfy({ abs($0.pan) <= maxPan }) else { return nil }
        let moved = last.world - first.world
        let speed = moved / (last.t - first.t)
        guard abs(speed) >= crossSpeed, abs(moved) >= crossDegrees else { return nil }
        let fast = abs(speed) * .pi / 180 * meters >= fastMetersPerSecond
        return .crossing(name: name, leftToRight: speed > 0, distance: Self.band(meters), fast: fast)
    }

    private func walkingAway(_ track: Track, bearing: Double, meters: Double, now: TimeInterval) -> ActionCaption? {
        let window = track.history.filter { $0.t >= now - awayWindow }
        guard window.count >= 3, let first = window.first, let last = window.last, last.t - first.t >= awayWindow * 0.75,
              first.height > 0, 1 - last.height / first.height >= shrink else { return nil }
        return .walkingAway(hour: Bearing(degrees: bearing, band: .ahead).clock, distance: Self.band(meters))
    }

    private mutating func noteMouths(_ faces: [TrackSnapshot], now: TimeInterval) {
        for f in faces { if let m = f.mouthOpenness { mouths[f.trackID, default: []].append((now, m)) } }
        for (id, series) in mouths { mouths[id] = series.filter { $0.t > now - mouthWindow } }
        mouths = mouths.filter { !$0.value.isEmpty }
    }

    /// Nil when the mouth is not readable (profile, too small): then speech nearby stands in.
    private func mouthMoving(_ f: TrackSnapshot) -> Bool? {
        guard let series = mouths[f.trackID], series.count >= mouthMinSamples else { return nil }
        let mean = series.reduce(0) { $0 + $1.openness } / Double(series.count)
        let variance = series.reduce(0) { $0 + ($1.openness - mean) * ($1.openness - mean) } / Double(series.count)
        return variance >= mouthVariance
    }

    private mutating func group(_ people: [Person], speech: Bool, now: TimeInterval) -> (caption: ActionCaption, meters: Double, signature: String)? {
        // Clusters of side-by-side neighbours at similar distance; the one whose nearest member is closest wins.
        var clusters: [[Person]] = []
        for p in people.sorted(by: { $0.bearing < $1.bearing }) {
            if let prev = clusters.last?.last,
               (p.bearing - prev.bearing) * .pi / 180 * min(p.meters, prev.meters) <= groupGapMeters,
               abs(Trajectory.rank(Self.band(p.meters)) - Trajectory.rank(Self.band(prev.meters))) <= 1 {
                clusters[clusters.count - 1].append(p)
            } else { clusters.append([p]) }
        }
        let near = clusters.filter { $0.count >= 2 && $0.map(\.meters).min()! <= groupMaxMeters }
        guard let g = near.min(by: { $0.map(\.meters).min()! < $1.map(\.meters).min()! }) else {
            if let c = groupCandidate, now - c.last > groupFlicker { groupCandidate = nil }
            if now - groupLastSeen > groupForget { announcedGroup = nil }
            return nil
        }
        groupLastSeen = now
        let names = g.compactMap(\.name).sorted()
        // Head counts flicker as faces turn away; the agreed people in it are what makes it a different group.
        let signature = names.joined(separator: ",")
        if let c = groupCandidate, c.signature == signature, now - c.last <= groupFlicker { groupCandidate = (signature, c.since, now) }
        else { groupCandidate = (signature, now, now) }
        guard let c = groupCandidate, now - c.since >= groupHold, signature != announcedGroup else { return nil }
        let faced = g.compactMap(\.facing)
        guard faced.filter({ $0 }).count * 2 <= faced.count else { return nil }
        let mouthsSeen = g.compactMap(\.talking)
        guard mouthsSeen.isEmpty ? speech : mouthsSeen.contains(true) else { return nil }
        let meters = g.map(\.meters).min()!
        let mid = g.map(\.bearing).reduce(0, +) / Double(g.count)
        let caption = ActionCaption.group(count: g.count, names: names, hour: Bearing(degrees: mid, band: .ahead).clock,
                                          distance: Self.band(meters), talking: true)
        return (caption, meters, signature)
    }

    static func band(_ m: Double) -> Distance { m < SpatialConfig.default.closeMaxMeters ? .close : m <= SpatialConfig.default.mediumMaxMeters ? .medium : .far }
    static func meters(_ d: Distance) -> Double { switch d { case .close: return 1; case .medium: return 2.2; case .far: return 4 } }
}

extension Phrasebook {
    /// "Someone crossing, left to right, close." · "Marcus hurrying past, right to left." · "Someone walking away,
    /// 1 o'clock." · "Three people talking together, 11 o'clock." · "Marcus and two others talking, 11 o'clock."
    static func action(_ c: ActionCaption) -> String {
        func far(_ d: Distance) -> String { d == .medium ? "" : ", \(d.words)" }
        switch c {
        case let .crossing(name, ltr, d, fast):
            return "\(name ?? "Someone") \(fast ? "hurrying past" : "crossing"), \(ltr ? "left to right" : "right to left")\(far(d))."
        case let .walkingAway(hour, _):
            return "Someone walking away, \(hour) o'clock."
        case let .group(count, names, hour, _, talking):
            let others = count - names.count
            var who = names
            if names.isEmpty { who = ["\(capitalized(countWord(count))) people"] }
            else if others > 0 { who.append(others == 1 ? "one other" : "\(countWord(others)) others") }
            let subject = who.count <= 1 ? who.joined() : who.dropLast().joined(separator: ", ") + " and " + who.last!
            let verb = talking ? (names.isEmpty ? "talking together" : "talking") : "together"
            return "\(subject) \(verb), \(hour) o'clock."
        }
    }

    static func countWord(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n < words.count ? words[n] : "\(n)"
    }

    /// Close crossings play while walking, so they are prewarmed with the alerts.
    static var actionAlertPhrases: [String] {
        [true, false].flatMap { ltr in [true, false].map { fast in action(.crossing(name: nil, leftToRight: ltr, distance: .close, fast: fast)) } }
    }
}
