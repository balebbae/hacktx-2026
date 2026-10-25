import XCTest
import CoreGraphics
@testable import Familiar

final class SpatialTests: XCTestCase {
    func testBearingCenterIsZeroAndEdgesAreHalfFOV() {
        XCTAssertEqual(Spatial.bearingDegrees(centerX: 0.5, hFOV: 53), 0, accuracy: 1e-6)
        XCTAssertEqual(Spatial.bearingDegrees(centerX: 1.0, hFOV: 53), 26.5, accuracy: 1e-6)
        XCTAssertEqual(Spatial.bearingDegrees(centerX: 0.0, hFOV: 53), -26.5, accuracy: 1e-6)
        XCTAssertLessThan(Spatial.bearingDegrees(centerX: 0.25, hFOV: 53), 0)
    }

    func testBands() {
        XCTAssertEqual(Spatial.band(centerX: 0.05), .farLeft)
        XCTAssertEqual(Spatial.band(centerX: 0.25), .left)
        XCTAssertEqual(Spatial.band(centerX: 0.5), .ahead)
        XCTAssertEqual(Spatial.band(centerX: 0.75), .right)
        XCTAssertEqual(Spatial.band(centerX: 0.95), .farRight)
    }

    func testDistanceFromFaceHeight() {
        // 0.20 m face spanning the whole 85° vertical FOV is ~11 cm away; a tiny face is far.
        XCTAssertEqual(Spatial.distance(faceHeightPx: 1280, frameHeightPx: 1280, vFOV: 85), .close)
        XCTAssertEqual(Spatial.distance(faceHeightPx: 190, frameHeightPx: 1280, vFOV: 85), .close)   // enroll_marcus ≈ 0.9 m
        XCTAssertEqual(Spatial.distance(faceHeightPx: 75, frameHeightPx: 1280, vFOV: 85), .medium)   // approach start ≈ 2.3 m
        XCTAssertEqual(Spatial.distance(faceHeightPx: 40, frameHeightPx: 1280, vFOV: 85), .far)
        var cfg = SpatialConfig.default; cfg.closeMaxMeters = 0.5
        XCTAssertEqual(Spatial.distance(faceHeightPx: 190, frameHeightPx: 1280, vFOV: 85, config: cfg), .medium)
    }
}

final class MatcherTests: XCTestCase {
    let marcus = UUID(), priya = UUID()
    func gallery(_ model: String = "w600k_mbf") -> Gallery {
        Gallery(modelID: model, people: [(marcus, "Marcus", [FakeEmbedder.vector(for: "marcus")]), (priya, "Priya", [FakeEmbedder.vector(for: "priya")])])
    }

    func testExactMatchAcceptedAndStrangerRejected() {
        let m = Matcher(config: .default)
        let hit = m.match(FakeEmbedder.vector(for: "marcus"), gallery: gallery(), modelID: "w600k_mbf")
        XCTAssertTrue(hit.accepted); XCTAssertEqual(hit.name, "Marcus"); XCTAssertEqual(hit.bestScore, 1, accuracy: 1e-4)
        let miss = m.match(FakeEmbedder.vector(for: "stranger"), gallery: gallery(), modelID: "w600k_mbf")
        XCTAssertFalse(miss.accepted); XCTAssertNil(miss.personID); XCTAssertLessThan(miss.bestScore, 0.4)
    }

    func testModelMismatchNeverMatches() {
        let r = Matcher(config: .default).match(FakeEmbedder.vector(for: "marcus"), gallery: gallery("other"), modelID: "w600k_mbf")
        XCTAssertFalse(r.accepted)
    }

    func testMarginRejectsAmbiguousMatch() {
        let a = FakeEmbedder.vector(for: "marcus"), b = FakeEmbedder.vector(for: "priya")
        let mid = Matcher.normalized(zip(a, b).map { $0 + $1 })
        let r = Matcher(config: MatcherConfig(threshold: 0.4, margin: 0.08)).match(mid, gallery: gallery(), modelID: "w600k_mbf")
        XCTAssertGreaterThan(r.bestScore, 0.4)
        XCTAssertFalse(r.accepted, "both people score the same, so the margin rule must refuse to name either")
    }

    func testVotesLockAfterThreeAndUnlockOnConflict() {
        var v = IdentityVotes(config: .default)
        let yes = MatchResult(personID: marcus, name: "Marcus", bestScore: 0.7, secondBestPersonScore: 0.1, accepted: true)
        let no = MatchResult(personID: nil, name: nil, bestScore: 0.2, secondBestPersonScore: 0.1, accepted: false)
        XCTAssertFalse(v.record(yes)); XCTAssertFalse(v.record(yes)); XCTAssertFalse(v.locked)
        XCTAssertTrue(v.record(yes)); XCTAssertTrue(v.locked); XCTAssertEqual(v.identity.name, "Marcus")
        XCTAssertFalse(v.record(no)); XCTAssertTrue(v.locked, "one bad frame does not unlock")
        _ = v.record(no); _ = v.record(no)
        XCTAssertFalse(v.locked, "sustained conflict unlocks")
        XCTAssertNil(v.identity.name)
    }
}

final class TrajectoryTests: XCTestCase {
    func obs(_ t: Double, _ h: Double, _ d: Distance) -> TrackObservation { TrackObservation(t: t, heightPx: h, distance: d) }

    func testApproachThenArriveOncePerEpisode() {
        var s = TrajectoryState()
        var h: [TrackObservation] = []
        var fired: [TrajectoryVerdict] = []
        let heights: [(Double, Double, Distance)] = [(0, 70, .medium), (0.5, 80, .medium), (1.0, 100, .medium), (1.3, 130, .close), (1.6, 180, .close), (2.0, 200, .close), (2.4, 205, .close), (2.7, 205, .close)]
        for (t, hp, d) in heights { h.append(obs(t, hp, d)); fired += Trajectory.evaluate(history: h, state: &s) }
        XCTAssertEqual(fired, [.approaching, .arrived])
        h.append(obs(3.0, 205, .close)); XCTAssertEqual(Trajectory.evaluate(history: h, state: &s), [])
    }

    func testStaticCloseFaceNeverApproaches() {
        var s = TrajectoryState(); var h: [TrackObservation] = []; var fired: [TrajectoryVerdict] = []
        for i in 0..<10 { h.append(obs(Double(i) * 0.3, 190, .close)); fired += Trajectory.evaluate(history: h, state: &s) }
        XCTAssertFalse(fired.contains(.approaching))
        XCTAssertEqual(fired.filter { $0 == .arrived }.count, 1)
    }

    func testGrowthRuleNeedsThreeObservations() {
        var s = TrajectoryState()
        XCTAssertEqual(Trajectory.evaluate(history: [obs(0, 50, .far), obs(0.5, 100, .medium)], state: &s), [])
    }
}

final class TrackerTests: XCTestCase {
    func det(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat = 0.2) -> FaceDetection { FaceDetection(box: CGRect(x: x, y: y, width: s, height: s), confidence: 0.9) }

    func testConfirmAfterThreeHitsAndLoseAfterTimeout() {
        let tr = FaceTracker(config: .default, matcher: .default)
        var u = tr.update([det(0.4, 0.4)], at: 0)
        XCTAssertEqual(u.created.count, 1); XCTAssertTrue(u.confirmed.isEmpty)
        u = tr.update([det(0.41, 0.4)], at: 0.1); XCTAssertTrue(u.confirmed.isEmpty)
        u = tr.update([det(0.42, 0.4)], at: 0.2)
        XCTAssertEqual(u.confirmed.count, 1); XCTAssertTrue(u.confirmed[0].isConfirmed)
        let id = u.confirmed[0].id
        u = tr.update([], at: 1.0); XCTAssertTrue(u.lost.isEmpty); XCTAssertNotNil(tr.track(id: id), "coasts through a short occlusion")
        u = tr.update([det(0.45, 0.4)], at: 1.5); XCTAssertEqual(u.tracks.first?.id, id, "reacquired with the same id")
        u = tr.update([], at: 4.5); XCTAssertEqual(u.lost.map(\.id), [id]); XCTAssertNil(tr.track(id: id))
    }

    func testTwoFacesKeepSeparateIDs() {
        let tr = FaceTracker(config: .default, matcher: .default)
        for i in 0..<4 { _ = tr.update([det(0.1, 0.4), det(0.7, 0.4)], at: Double(i) * 0.1) }
        XCTAssertEqual(tr.tracks.count, 2)
        XCTAssertEqual(Set(tr.tracks.map(\.id)).count, 2)
        XCTAssertTrue(tr.tracks.allSatisfy(\.isConfirmed))
    }

    func testBestEmbeddingsKeepsTopEightByQuality() {
        let t = FaceTrack(id: 1, detection: det(0.4, 0.4), at: 0, matcher: .default)
        for i in 0..<12 {
            let e = FaceEmbedding(modelID: "w600k_mbf", vector: FakeEmbedder.vector(for: "m\(i)"), quality: Float(i) / 12, timestamp: Double(i), thumbnailJPEG: nil)
            t.addEmbedding(ScoredEmbedding(embedding: e, yawDegrees: Double(i % 3) * 10), max: 8)
        }
        let best = t.bestEmbeddings(max: 8)
        XCTAssertEqual(best.count, 8)
        XCTAssertEqual(best.map(\.quality), best.map(\.quality).sorted(by: >))
        XCTAssertEqual(t.bestEmbeddings(max: 3).count, 3)
    }

    func testFactoryAndFakeEmbedder() async throws {
        let p = PerceptionFactory.make(embedder: FakeEmbedder(label: "marcus"), threshold: 0.55)
        XCTAssertEqual(p.matcher.config.threshold, 0.55)
        XCTAssertEqual(p.embedder.modelID, "w600k_mbf")
        let buf = try XCTUnwrap(FaceAligner.makeBuffer(width: 112, height: 112))
        let v = try await p.embedder.embed(buf)
        XCTAssertEqual(v.count, 512)
        XCTAssertEqual(Matcher.cosine(v, FakeEmbedder.vector(for: "marcus")), 1, accuracy: 1e-4)
        XCTAssertTrue(p.currentTracks().isEmpty)
    }
}
