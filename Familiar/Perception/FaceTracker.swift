import Foundation
import CoreGraphics

struct TrackerConfig: Equatable {
    var iouThreshold: Double = 0.3
    var confirmHits = 3
    /// Seconds unseen before a track is dropped.
    var lostAfter: TimeInterval = 2.5
    var maxEmbeddings = 8
    /// Keep box history this long (seconds); the trajectory window reads from it.
    var historySeconds: TimeInterval = 3.0
    var mouthSeriesSeconds: TimeInterval = 1.5
    var facingYawDegrees: Double = 25
    static let `default` = TrackerConfig()
}

/// Mutable per-face state owned by `FaceTracker`. Reference type so the pipeline can annotate it in place.
final class FaceTrack {
    enum Status: Equatable { case tentative, confirmed }

    let id: Int
    let firstSeen: TimeInterval
    private(set) var lastSeen: TimeInterval
    private(set) var hits = 0
    private(set) var status: Status = .tentative
    private(set) var detection: FaceDetection
    private(set) var history: [TrackObservation] = []
    private(set) var mouthSeries: [(t: TimeInterval, openness: Double)] = []
    private(set) var embeddings: [ScoredEmbedding] = []

    var votes: IdentityVotes
    var trajectory = TrajectoryState()
    var lastEmbeddedAt: TimeInterval = -.infinity
    var burstUntil: TimeInterval = 0
    var confirmedAt: TimeInterval?
    var appearedAnnounced = false
    var lastKnownBearing: Bearing?
    var distance: Distance = .far
    /// Upright pixel height of the last box, used by the pipeline's quality/scheduling decisions.
    var faceHeightPx: Int = 0
    /// Set by the pipeline when it last published a snapshot for this track.
    var lastSnapshot: TrackSnapshot?

    init(id: Int, detection: FaceDetection, at t: TimeInterval, matcher: MatcherConfig) {
        self.id = id; self.firstSeen = t; self.lastSeen = t; self.detection = detection
        self.votes = IdentityVotes(config: matcher)
    }

    var box: CGRect { detection.box }
    var yawDegrees: Double? { detection.yawDegrees }
    var isFacingUser: Bool { abs(detection.yawDegrees ?? 0) < 25 }
    var isKnown: Bool { votes.locked }
    var identity: Identity { votes.identity }
    var isConfirmed: Bool { status == .confirmed }

    fileprivate func seen(_ d: FaceDetection, at t: TimeInterval, config: TrackerConfig) {
        detection = d
        lastSeen = t
        hits += 1
        if status == .tentative, hits >= config.confirmHits { status = .confirmed; confirmedAt = t }
        if let m = d.mouthOpenness {
            mouthSeries.append((t, m))
            mouthSeries.removeAll { $0.t < t - config.mouthSeriesSeconds }
        }
    }

    func observe(heightPx: Double, distance: Distance, at t: TimeInterval, config: TrackerConfig) {
        history.append(TrackObservation(t: t, heightPx: heightPx, distance: distance))
        history.removeAll { $0.t < t - config.historySeconds }
        self.distance = distance
        faceHeightPx = Int(heightPx.rounded())
    }

    /// Mean mouth openness over the series, or the latest value.
    var mouthOpenness: Double? { mouthSeries.last?.openness }

    /// Keep the best `max` by quality x yaw diversity. Diversity rewards poses at least 15° apart from the rest.
    func addEmbedding(_ e: ScoredEmbedding, max maxCount: Int) {
        embeddings.append(e)
        guard embeddings.count > maxCount else { return }
        func rank(_ i: Int) -> Float {
            let yaw = embeddings[i].yawDegrees
            let nearest = embeddings.enumerated().filter { $0.offset != i }.map { abs($0.element.yawDegrees - yaw) }.min() ?? 90
            let diversity = Float(min(1, nearest / 15) * 0.5 + 0.5)
            return embeddings[i].embedding.quality * diversity
        }
        if let worst = embeddings.indices.min(by: { rank($0) < rank($1) }) { embeddings.remove(at: worst) }
    }

    func bestEmbeddings(max maxCount: Int) -> [FaceEmbedding] {
        Array(embeddings.map(\.embedding).sorted { $0.quality > $1.quality }.prefix(maxCount))
    }
}

/// Greedy IoU association frame to frame. Not thread-safe: the pipeline calls it from one loop under its lock.
final class FaceTracker {
    let config: TrackerConfig
    let matcher: MatcherConfig
    private(set) var tracks: [FaceTrack] = []
    private var nextID = 1

    init(config: TrackerConfig = .default, matcher: MatcherConfig = .default) { self.config = config; self.matcher = matcher }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let i = Double(inter.width * inter.height)
        let u = Double(a.width * a.height + b.width * b.height) - i
        return u > 0 ? i / u : 0
    }

    struct Update {
        var tracks: [FaceTrack]
        var lost: [FaceTrack]
        var created: [FaceTrack]
        var confirmed: [FaceTrack]
    }

    @discardableResult
    func update(_ detections: [FaceDetection], at t: TimeInterval) -> Update {
        var pairs: [(iou: Double, track: Int, det: Int)] = []
        for (ti, tr) in tracks.enumerated() {
            for (di, d) in detections.enumerated() {
                let v = Self.iou(tr.box, d.box)
                if v > config.iouThreshold { pairs.append((v, ti, di)) }
            }
        }
        pairs.sort { $0.iou > $1.iou }
        var usedTracks = Set<Int>(), usedDets = Set<Int>()
        var confirmedNow: [FaceTrack] = []
        for p in pairs where !usedTracks.contains(p.track) && !usedDets.contains(p.det) {
            usedTracks.insert(p.track); usedDets.insert(p.det)
            let tr = tracks[p.track]
            let was = tr.status
            tr.seen(detections[p.det], at: t, config: config)
            if was == .tentative, tr.status == .confirmed { confirmedNow.append(tr) }
        }
        // Second pass for faces that moved while occluded: nearest unseen track whose centre is within one box width.
        for (di, d) in detections.enumerated() where !usedDets.contains(di) {
            var best: (dist: Double, idx: Int)?
            for (ti, tr) in tracks.enumerated() where !usedTracks.contains(ti) && t - tr.lastSeen > 0.2 {
                let dx = Double(tr.box.midX - d.box.midX), dy = Double(tr.box.midY - d.box.midY)
                let dist = sqrt(dx * dx + dy * dy)
                let limit = Double(max(tr.box.width, d.box.width))
                if dist < limit, best == nil || dist < best!.dist { best = (dist, ti) }
            }
            if let best {
                usedTracks.insert(best.idx); usedDets.insert(di)
                let tr = tracks[best.idx]
                let was = tr.status
                tr.seen(d, at: t, config: config)
                if was == .tentative, tr.status == .confirmed { confirmedNow.append(tr) }
            }
        }
        var created: [FaceTrack] = []
        for (di, d) in detections.enumerated() where !usedDets.contains(di) {
            let tr = FaceTrack(id: nextID, detection: d, at: t, matcher: matcher)
            nextID += 1
            tr.seen(d, at: t, config: config)
            tracks.append(tr)
            created.append(tr)
        }
        var lost: [FaceTrack] = []
        tracks.removeAll { tr in
            let gone = t - tr.lastSeen > (tr.status == .confirmed ? config.lostAfter : min(config.lostAfter, 0.5))
            if gone { lost.append(tr) }
            return gone
        }
        return Update(tracks: tracks, lost: lost, created: created, confirmed: confirmedNow)
    }

    func track(id: Int) -> FaceTrack? { tracks.first { $0.id == id } }

    /// Tracks seen in the current frame (not coasting through an occlusion).
    func visible(at t: TimeInterval, tolerance: TimeInterval = 0.05) -> [FaceTrack] { tracks.filter { t - $0.lastSeen <= tolerance } }

    func removeAll() { tracks.removeAll() }
}
