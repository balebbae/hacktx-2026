import Foundation
import CoreGraphics
import CoreVideo
import QuartzCore
import os

struct PipelineConfig: Equatable {
    var maxFPS: Double = 15
    var snapshotEvery = 5
    var previewMaxWidth: CGFloat = 240
    /// Embedding cadence, seconds between embeds per track.
    var unlockedInterval: TimeInterval = 0.5
    var lockedInterval: TimeInterval = 3.0
    var unknownInterval: TimeInterval = 1.0
    var unknownSlowAfter: TimeInterval = 10
    var unknownSlowInterval: TimeInterval = 5.0
    var burstInterval: TimeInterval = 0.25
    /// Automatic burst when a track is confirmed so a known person is named within about a second.
    var confirmBurstSeconds: TimeInterval = 1.5
    var maxEmbedsPerFrame = 2
    var exposureUpdateInterval: TimeInterval = 1.0
    static let `default` = PipelineConfig()
}

/// Frames → Vision detection → IoU tracking → ArcFace alignment → embedding → gallery match → events.
final class PerceptionPipeline: Perception, @unchecked Sendable {
    let embedder: EmbeddingProvider
    let detector: FaceDetector
    let aligner: FaceAligner
    let tracker: FaceTracker
    let matcher: Matcher
    let spatial: SpatialConfig
    let trajectory: TrajectoryConfig
    let config: PipelineConfig

    private let bus = EventBus<PerceptionEvent>()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var loop: Task<Void, Never>?
    private weak var gallery: GalleryProvider?
    private weak var frameSource: FrameSource?

    private struct State {
        var snapshots: [TrackSnapshot] = []
        var unknownCount = 0
        var processed = 0
        var lastProcessedAt: TimeInterval = -.infinity
        var lastExposureAt: TimeInterval = -.infinity
        var running = false
        var pendingBursts: [Int: TimeInterval] = [:]
        var pendingAssignments: [Int: (UUID, String)] = [:]
    }

    /// Diagnostics for the judge view and tests.
    struct Stats: Equatable { var framesProcessed = 0; var embeddings = 0; var detectMillis = 0.0; var embedMillis = 0.0; var fps = 0.0 }
    private let statsLock = OSAllocatedUnfairLock(initialState: Stats())
    var stats: Stats { statsLock.withLock { $0 } }
    /// Every accepted/rejected match score, for the cosine distributions in the test log.
    private(set) var matchLog: [(trackID: Int, personName: String?, bestScore: Float, accepted: Bool)] = []
    private let matchLogLock = OSAllocatedUnfairLock(initialState: ())

    init(embedder: EmbeddingProvider, detector: FaceDetector = FaceDetector(), aligner: FaceAligner = .shared,
         matcher: MatcherConfig = .default, tracker: TrackerConfig = .default, spatial: SpatialConfig = .default,
         trajectory: TrajectoryConfig = .default, config: PipelineConfig = .default) {
        self.embedder = embedder
        self.detector = detector
        self.aligner = aligner
        self.matcher = Matcher(config: matcher)
        var trackerConfig = tracker
        trackerConfig.lostAfter = trajectory.lostAfter
        self.tracker = FaceTracker(config: trackerConfig, matcher: matcher)
        self.spatial = spatial
        self.trajectory = trajectory
        self.config = config
    }

    // MARK: - Perception

    func subscribe() -> AsyncStream<PerceptionEvent> { bus.subscribe() }

    func start(frames: FrameSource, gallery: GalleryProvider) async throws {
        guard loop == nil else { return }
        tracker.removeAll()
        lock.withLock { s in s.snapshots = []; s.unknownCount = 0; s.processed = 0; s.lastProcessedAt = -.infinity }
        matchLogLock.withLock { _ in matchLog.removeAll() }
        self.gallery = gallery
        self.frameSource = frames
        lock.withLock { $0.running = true }
        let stream = frames.subscribe()
        loop = Task.detached(priority: .userInitiated) { [weak self] in
            for await frame in stream {
                guard let self, !Task.isCancelled else { break }
                await self.process(frame)
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        lock.withLock { $0.running = false }
        bus.finishAll()   // tracks and snapshots stay readable until the next start() (consent flow reads them after stop)
    }

    func currentTracks() -> [TrackSnapshot] { lock.withLock { $0.snapshots } }

    func bestEmbeddings(track: Int, max: Int) -> [FaceEmbedding] {
        lock.withLock { _ in tracker.track(id: track)?.bestEmbeddings(max: max) ?? [] }
    }

    func requestBurst(track: Int, seconds: Double) {
        lock.withLock { $0.pendingBursts[track] = seconds }
    }

    func assignIdentity(track: Int, personID: UUID, name: String) {
        let snaps: [TrackSnapshot] = lock.withLock { s in
            if let t = tracker.track(id: track) {
                t.votes.assign(personID: personID, name: name)
                t.appearedAnnounced = true
                s.snapshots = s.snapshots.map { $0.trackID == track ? $0.relabeled(t.identity) : $0 }
            } else {
                s.pendingAssignments[track] = (personID, name)
            }
            return s.snapshots
        }
        bus.publish(.snapshot(tracks: snaps, preview: nil))
    }

    // MARK: - Frame loop

    private func process(_ frame: Frame) async {
        let now = frame.timestamp
        let skip = lock.withLock { s -> Bool in
            if now - s.lastProcessedAt < 1 / config.maxFPS { return true }
            s.lastProcessedAt = now; return false
        }
        if skip { return }
        guard let result = await detector.detect(frame) else { return }
        let hostNow = CACurrentMediaTime()

        var events: [PerceptionEvent] = []
        let update = lock.withLock { _ in tracker.update(result.detections, at: now) }

        // Trajectory + geometry per confirmed track; left events for lost known tracks.
        for t in update.lost where t.isConfirmed && t.isKnown {
            if let id = t.identity.personID, let name = t.identity.name {
                events.append(.knownLeft(personID: id, name: name, last: t.lastKnownBearing ?? Bearing(degrees: 0, band: .ahead)))
            }
        }
        var embedCandidates: [FaceTrack] = []
        lock.withLock { s in
            for t in update.confirmed {
                t.burstUntil = max(t.burstUntil, now + config.confirmBurstSeconds)
                if let (pid, name) = s.pendingAssignments.removeValue(forKey: t.id) { t.votes.assign(personID: pid, name: name); t.appearedAnnounced = true }
            }
            for (id, secs) in s.pendingBursts { if let t = tracker.track(id: id) { t.burstUntil = max(t.burstUntil, now + secs) } }
            s.pendingBursts.removeAll()
            for t in tracker.visible(at: now) {
                let heightPx = Double(t.box.height) * Double(result.uprightSize.height)
                let dist = Spatial.distance(faceHeightPx: heightPx, frameHeightPx: Double(result.uprightSize.height), vFOV: frame.verticalFOVDegrees, config: spatial)
                t.observe(heightPx: heightPx, distance: dist, at: now, config: tracker.config)
                t.lastKnownBearing = Spatial.bearing(centerX: Double(t.box.midX), hFOV: frame.horizontalFOVDegrees)
                guard t.isConfirmed else { continue }
                if shouldEmbed(t, now: now) { embedCandidates.append(t) }
            }
        }

        // Embedding: largest faces first, at most `maxEmbedsPerFrame` per frame.
        embedCandidates.sort { $0.box.height > $1.box.height }
        var embedsThisFrame = 0
        for t in embedCandidates.prefix(config.maxEmbedsPerFrame) {
            guard let lm = t.detection.landmarks, let aligned = aligner.align(frame.pixelBuffer, orientation: frame.orientation, landmarks: lm) else { continue }
            t.lastEmbeddedAt = now
            let t0 = CACurrentMediaTime()
            guard let vector = try? await embedder.embed(aligned.buffer) else { continue }
            let embedMs = (CACurrentMediaTime() - t0) * 1000
            embedsThisFrame += 1
            var quality = Self.quality(heightPx: Double(t.box.height) * Double(result.uprightSize.height), yaw: t.yawDegrees, confidence: t.detection.confidence)
            if t.detection.landmarkSource == .box { quality *= 0.9 }
            let thumb = aligner.thumbnail(frame.pixelBuffer, orientation: frame.orientation, box: t.box)
            let emb = FaceEmbedding(modelID: embedder.modelID, vector: vector, quality: quality, timestamp: now, thumbnailJPEG: thumb)
            let gal = gallery?.gallery() ?? Gallery(modelID: embedder.modelID, people: [])
            let match = matcher.match(vector, gallery: gal, modelID: embedder.modelID)
            matchLogLock.withLock { _ in matchLog.append((t.id, match.name ?? (match.bestScore > 0 ? gal.people.max { a, b in (a.embeddings.map { Matcher.cosine($0, vector) }.max() ?? 0) < (b.embeddings.map { Matcher.cosine($0, vector) }.max() ?? 0) }?.name : nil), match.bestScore, match.accepted)) }
            let becameKnown: Bool = lock.withLock { _ in
                t.addEmbedding(ScoredEmbedding(embedding: emb, yawDegrees: t.yawDegrees ?? 0), max: tracker.config.maxEmbeddings)
                return t.votes.record(match)
            }
            statsLock.withLock { $0.embeddings += 1; $0.embedMillis = $0.embedMillis * 0.8 + embedMs * 0.2 }
            if becameKnown, !t.appearedAnnounced {
                t.appearedAnnounced = true
                events.append(.knownAppeared(snapshot(for: t, frame: frame, upright: result.uprightSize, now: now)))
            }
        }

        // Trajectory verdicts for known tracks (history includes pre-lock observations, so an approach that started
        // before the name locked still fires).
        var snaps: [TrackSnapshot] = []
        lock.withLock { s in
            for t in tracker.visible(at: now) where t.isConfirmed {
                let snap = snapshot(for: t, frame: frame, upright: result.uprightSize, now: now)
                t.lastSnapshot = snap
                snaps.append(snap)
                // Only evaluate once the name is locked; otherwise an approach that happened while the face was still
                // "someone" would be consumed silently and never spoken.
                guard t.isKnown else { continue }
                let verdicts = Trajectory.evaluate(history: t.history, state: &t.trajectory, config: trajectory)
                for v in verdicts {
                    switch v {
                    case .approaching: events.append(.knownApproaching(snap))
                    case .arrived: events.append(.knownArrived(snap))
                    }
                }
            }
            // Coasting confirmed tracks (briefly occluded) stay in the snapshot with their last pose.
            for t in tracker.tracks where t.isConfirmed && !snaps.contains(where: { $0.trackID == t.id }) {
                if let last = t.lastSnapshot { snaps.append(last.relabeled(t.identity)) }
            }
            s.snapshots = snaps.sorted { $0.trackID < $1.trackID }
            let unknown = tracker.tracks.filter { $0.isConfirmed && !$0.isKnown }.count
            if unknown != s.unknownCount { s.unknownCount = unknown; events.append(.unknownCountChanged(unknown)) }
            s.processed += 1
        }

        let processed = lock.withLock { $0.processed }
        statsLock.withLock { st in
            st.framesProcessed = processed
            st.detectMillis = st.detectMillis * 0.8 + detector.lastDurationMillis * 0.2
            let dt = CACurrentMediaTime() - hostNow
            _ = dt
        }
        for e in events { bus.publish(e) }
        if processed % config.snapshotEvery == 0 {
            let preview = aligner.cgImage(frame.pixelBuffer, orientation: frame.orientation, maxWidth: config.previewMaxWidth)
            bus.publish(.snapshot(tracks: snaps, preview: preview))
        }
        updateExposure(now: now)
    }

    private func shouldEmbed(_ t: FaceTrack, now: TimeInterval) -> Bool {
        guard t.detection.landmarks != nil else { return false }
        let since = now - t.lastEmbeddedAt
        if now < t.burstUntil { return since >= config.burstInterval }
        if t.isKnown { return since >= config.lockedInterval }
        if t.votes.count > 0 { return since >= config.unlockedInterval }
        let age = now - (t.confirmedAt ?? t.firstSeen)
        return since >= (age < config.unknownSlowAfter ? config.unknownInterval : config.unknownSlowInterval)
    }

    private func snapshot(for t: FaceTrack, frame: Frame, upright: CGSize, now: TimeInterval) -> TrackSnapshot {
        let heightPx = Double(t.box.height) * Double(upright.height)
        return TrackSnapshot(trackID: t.id, identity: t.identity,
                             bearing: Spatial.bearing(centerX: Double(t.box.midX), hFOV: frame.horizontalFOVDegrees),
                             distance: t.distance, faceBox: t.box, faceHeightPx: Int(heightPx.rounded()),
                             yawDegrees: t.yawDegrees, isFacingUser: t.isFacingUser, mouthOpenness: t.mouthOpenness,
                             quality: Self.quality(heightPx: heightPx, yaw: t.yawDegrees, confidence: t.detection.confidence), timestamp: now)
    }

    /// Bigger, frontal, confident faces embed better: height saturates at 120 px, yaw as cos, confidence linear.
    static func quality(heightPx: Double, yaw: Double?, confidence: Float) -> Float {
        let size = Float(min(1, heightPx / 120))
        let pose = Float(max(0.2, cos((yaw ?? 0) * .pi / 180)))
        return max(0, min(1, size * pose * max(0.5, confidence)))
    }

    private func updateExposure(now: TimeInterval) {
        guard let cam = frameSource as? PhoneCameraFrameSource else { return }
        let due = lock.withLock { s -> Bool in
            guard now - s.lastExposureAt >= config.exposureUpdateInterval else { return false }
            s.lastExposureAt = now; return true
        }
        guard due, let largest = currentTracks().max(by: { $0.faceBox.height < $1.faceBox.height }) else { return }
        cam.setExposurePoint(CGPoint(x: largest.faceBox.midX, y: largest.faceBox.midY))
    }
}

/// What S5 calls from `Services.make`.
enum PerceptionFactory {
    static func make(embedder: EmbeddingProvider, threshold: Float) -> PerceptionPipeline {
        var m = MatcherConfig.default
        m.threshold = threshold
        return PerceptionPipeline(embedder: embedder, matcher: m)
    }

    /// On-device ORT when the model is bundled, with the Modal embedder as a fallback when configured;
    /// `FakeEmbedder` only when the model is missing.
    static func defaultEmbedder(bundle: Bundle = .main) -> EmbeddingProvider {
        guard let onDevice = OnDeviceEmbedder(bundle: bundle) else { return ModalEmbedder() ?? FakeEmbedder() }
        if let modal = ModalEmbedder() { return FallbackEmbedder(primary: onDevice, fallback: modal) }
        return onDevice
    }
}
