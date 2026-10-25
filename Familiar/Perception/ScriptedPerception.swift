import Foundation
import CoreGraphics
import QuartzCore
import UIKit
import os

/// Fake `Perception` driven by `Resources/Fixtures/script.json`. Emits the scripted events on a host-clock timer,
/// synthesizes plausible `TrackSnapshot`s and a preview image, and keeps `currentTracks()` consistent with the script.
final class ScriptedPerception: Perception, @unchecked Sendable {
    typealias Clock = () -> TimeInterval

    private let bus = EventBus<PerceptionEvent>()
    private let clock: Clock
    private let events: [ScriptEvent]
    private let snapshotInterval: TimeInterval
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var loop: Task<Void, Never>?
    var loops = true
    /// Speed multiplier for tests.
    var rate: Double = 1.0

    private struct TrackState { var snapshot: TrackSnapshot; var personID: UUID?; var name: String?; var burstUntil: TimeInterval = 0 }
    private struct State {
        var tracks: [Int: TrackState] = [:]
        var unknownCount = 0
        var people: [String: UUID] = [:]
        var startedAt: TimeInterval = 0
        var running = false
    }

    init(events: [ScriptEvent], clock: @escaping Clock = { CACurrentMediaTime() }, snapshotInterval: TimeInterval = 0.2) {
        self.events = events.sorted { $0.t < $1.t }
        self.clock = clock
        self.snapshotInterval = snapshotInterval
    }

    convenience init(scriptNamed name: String = "script", bundle: Bundle = .main, clock: @escaping Clock = { CACurrentMediaTime() }) {
        let url = bundle.url(forResource: name, withExtension: "json")
        let events = url.flatMap { try? JSONDecoder().decode([ScriptEvent].self, from: Data(contentsOf: $0)) } ?? ScriptedPerception.defaultScript
        self.init(events: events, clock: clock)
    }

    func subscribe() -> AsyncStream<PerceptionEvent> { bus.subscribe() }

    func start(frames: FrameSource, gallery: GalleryProvider) async throws {
        guard loop == nil else { return }
        lock.withLock { $0.running = true; $0.startedAt = clock() }
        loop = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            repeat {
                let began = self.clock()
                self.lock.withLock { $0.tracks.removeAll(); $0.unknownCount = 0; $0.startedAt = began }
                var next = 0
                var lastSnapshot = began
                while !Task.isCancelled {
                    let now = self.clock()
                    let elapsed = (now - began) * self.rate
                    while next < self.events.count, self.events[next].t <= elapsed {
                        self.apply(self.events[next], now: now)
                        next += 1
                    }
                    if now - lastSnapshot >= self.snapshotInterval {
                        lastSnapshot = now
                        self.bus.publish(.snapshot(tracks: self.currentTracks(), preview: self.renderPreview()))
                    }
                    if next >= self.events.count { break }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                // hold the final state for a moment before looping
                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 / max(self.rate, 0.01)))
            } while self.loops && !Task.isCancelled
            self.lock.withLock { $0.running = false }
        }
    }

    func stop() { loop?.cancel(); loop = nil; lock.withLock { $0.running = false } }

    func currentTracks() -> [TrackSnapshot] {
        let now = clock()
        return lock.withLock { s in
            s.tracks.values.map { ts in
                var snap = ts.snapshot
                snap = TrackSnapshot(trackID: snap.trackID, identity: snap.identity, bearing: snap.bearing, distance: snap.distance, faceBox: snap.faceBox, faceHeightPx: snap.faceHeightPx, yawDegrees: snap.yawDegrees, isFacingUser: snap.isFacingUser, mouthOpenness: snap.mouthOpenness, quality: snap.quality, timestamp: now)
                return snap
            }.sorted { $0.trackID < $1.trackID }
        }
    }

    func bestEmbeddings(track: Int, max: Int) -> [FaceEmbedding] {
        let seed = lock.withLock { $0.tracks[track]?.name ?? "track\(track)" }
        let now = clock()
        return (0..<Swift.max(0, Swift.min(max, 3))).map { i in
            FaceEmbedding(modelID: "fake", vector: Self.unitVector(seed: "\(seed)#\(i)"), quality: Float(0.9 - 0.1 * Double(i)), timestamp: now - Double(i) * 0.25, thumbnailJPEG: Self.placeholderThumbnail())
        }
    }

    func requestBurst(track: Int, seconds: Double) {
        let until = clock() + seconds
        lock.withLock { $0.tracks[track]?.burstUntil = until }
    }

    func assignIdentity(track: Int, personID: UUID, name: String) {
        lock.withLock { s in
            guard var ts = s.tracks[track] else { return }
            ts.personID = personID; ts.name = name
            ts.snapshot = Self.relabel(ts.snapshot, identity: .known(personID: personID, name: name, score: 0.71))
            s.tracks[track] = ts
            s.people[name] = personID
            s.unknownCount = s.tracks.values.filter { $0.personID == nil }.count
        }
        bus.publish(.unknownCountChanged(lock.withLock { $0.unknownCount }))
    }

    // MARK: - Script application

    private func apply(_ e: ScriptEvent, now: TimeInterval) {
        switch e.event {
        case "unknownCountChanged":
            let count = e.count ?? 0
            lock.withLock { s in
                let unknownIDs = s.tracks.filter { $0.value.personID == nil }.keys.sorted()
                if unknownIDs.count > count { for id in unknownIDs.suffix(unknownIDs.count - count) { s.tracks[id] = nil } }
                else if unknownIDs.count < count {
                    for i in 0..<(count - unknownIDs.count) {
                        let id = (s.tracks.keys.max() ?? 0) + 1
                        let band = BearingBand.all[(id + i) % BearingBand.all.count]
                        let snap = Self.makeSnapshot(trackID: id, identity: .unknown(bestScore: 0.21), band: band, distance: .medium, now: now)
                        s.tracks[id] = TrackState(snapshot: snap, personID: nil, name: nil)
                    }
                }
                s.unknownCount = count
            }
            bus.publish(.unknownCountChanged(count))
        case "knownAppeared", "knownApproaching", "knownArrived", "speakingStarted", "cue":
            let name = e.name ?? "Marcus"
            let snap: TrackSnapshot = lock.withLock { s in
                let pid = s.people[name] ?? UUID()
                s.people[name] = pid
                let id = e.trackID ?? s.tracks.first { $0.value.name == name }?.key ?? ((s.tracks.keys.max() ?? 0) + 1)
                let snap = Self.makeSnapshot(trackID: id, identity: .known(personID: pid, name: name, score: 0.71), band: e.bearingBand, distance: e.distanceBin, now: now)
                s.tracks[id] = TrackState(snapshot: snap, personID: pid, name: name, burstUntil: s.tracks[id]?.burstUntil ?? 0)
                return snap
            }
            switch e.event {
            case "knownAppeared": bus.publish(.knownAppeared(snap))
            case "knownApproaching": bus.publish(.knownApproaching(snap))
            case "knownArrived": bus.publish(.knownArrived(snap))
            case "speakingStarted": bus.publish(.speakingStarted(snap))
            default: bus.publish(.cue(personID: snap.identity.personID ?? UUID(), name: name, kind: e.kind == "smile" ? .smile : .wave))
            }
        case "knownLeft":
            let name = e.name ?? "Marcus"
            let (pid, bearing): (UUID, Bearing) = lock.withLock { s in
                let entry = s.tracks.first { $0.value.name == name }
                let pid = s.people[name] ?? entry?.value.personID ?? UUID()
                let bearing = entry?.value.snapshot.bearing ?? Bearing(degrees: 0, band: .ahead)
                if let key = entry?.key { s.tracks[key] = nil }
                return (pid, bearing)
            }
            bus.publish(.knownLeft(personID: pid, name: name, last: bearing))
        default:
            break
        }
    }

    // MARK: - Synthesis helpers

    static func makeSnapshot(trackID: Int, identity: Identity, band: BearingBand, distance: Distance, now: TimeInterval, hFOV: Double = 53) -> TrackSnapshot {
        let h = distance.typicalFaceHeightFraction
        let w = h * 0.75 * (1280.0 / 720.0)   // portrait frame: faces are narrower than tall in normalized units
        let cx = band.frameCenterX
        let box = CGRect(x: max(0, cx - w / 2), y: 0.38 - h / 2, width: w, height: h)
        return TrackSnapshot(trackID: trackID, identity: identity, bearing: Bearing(degrees: band.centerDegrees(hFOV: hFOV), band: band), distance: distance, faceBox: box, faceHeightPx: Int(h * 1280), yawDegrees: 0, isFacingUser: true, mouthOpenness: 0.02, quality: 0.8, timestamp: now)
    }

    static func relabel(_ s: TrackSnapshot, identity: Identity) -> TrackSnapshot {
        TrackSnapshot(trackID: s.trackID, identity: identity, bearing: s.bearing, distance: s.distance, faceBox: s.faceBox, faceHeightPx: s.faceHeightPx, yawDegrees: s.yawDegrees, isFacingUser: s.isFacingUser, mouthOpenness: s.mouthOpenness, quality: s.quality, timestamp: s.timestamp)
    }

    static func unitVector(seed: String, dimension: Int = 512) -> [Float] {
        var state: UInt64 = 1469598103934665603
        for b in seed.utf8 { state = (state ^ UInt64(b)) &* 1099511628211 }
        var v = [Float](repeating: 0, count: dimension)
        for i in 0..<dimension {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            v[i] = Float(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1
        }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return v.map { $0 / max(norm, 1e-6) }
    }

    private static let thumbnailCache = OSAllocatedUnfairLock<Data?>(initialState: nil)
    static func placeholderThumbnail() -> Data? {
        thumbnailCache.withLock { cached in
            if let cached { return cached }
            let size = CGSize(width: 256, height: 256)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.systemGray4.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.systemGray.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 78, y: 48, width: 100, height: 100))
                ctx.cgContext.fillEllipse(in: CGRect(x: 48, y: 150, width: 160, height: 140))
            }
            cached = img.jpegData(compressionQuality: 0.8)
            return cached
        }
    }

    /// A dark portrait frame with soft blobs where the scripted faces are, so the judge view has something behind its boxes.
    private func renderPreview() -> CGImage? {
        let size = CGSize(width: 180, height: 320)
        let tracks = currentTracks()
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for t in tracks {
                let r = CGRect(x: t.faceBox.minX * size.width, y: t.faceBox.minY * size.height, width: t.faceBox.width * size.width, height: t.faceBox.height * size.height)
                UIColor(white: 0.35, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: r.insetBy(dx: r.width * 0.1, dy: 0))
            }
        }
        return img.cgImage
    }

    /// Built-in 60 s walk of the demo, used when script.json is missing.
    static let defaultScript: [ScriptEvent] = [
        ScriptEvent(t: 1, event: "unknownCountChanged", count: 3),
        ScriptEvent(t: 8, event: "knownAppeared", name: "Marcus", band: "farRight", distance: "far", trackID: 10),
        ScriptEvent(t: 13, event: "knownApproaching", name: "Marcus", band: "right", distance: "medium", trackID: 10),
        ScriptEvent(t: 18, event: "knownArrived", name: "Marcus", band: "ahead", distance: "close", trackID: 10),
        ScriptEvent(t: 24, event: "speakingStarted", name: "Marcus", band: "ahead", distance: "close", trackID: 10),
        ScriptEvent(t: 30, event: "unknownCountChanged", count: 1),
        ScriptEvent(t: 36, event: "knownLeft", name: "Marcus"),
        ScriptEvent(t: 48, event: "knownAppeared", name: "Marcus", band: "left", distance: "medium", trackID: 11),
        ScriptEvent(t: 54, event: "knownArrived", name: "Marcus", band: "ahead", distance: "close", trackID: 11),
        ScriptEvent(t: 60, event: "unknownCountChanged", count: 0),
    ]
}
