import XCTest
import AVFoundation
@testable import Familiar

/// End-to-end: real Vision + ORT pipeline over the bundled clips, played in real time by `VideoFileFrameSource`.
/// Builds Marcus's gallery from `enroll_marcus.mp4`, then checks approach / strangers / mixed / leave.
final class PerceptionFixtureTests: XCTestCase {
    final class StaticGallery: GalleryProvider, @unchecked Sendable {
        var value: Gallery
        init(_ g: Gallery) { value = g }
        func gallery() -> Gallery { value }
    }
    final class Box<T>: @unchecked Sendable { var items: [T] = []; let lock = NSLock(); func add(_ t: T) { lock.lock(); items.append(t); lock.unlock() } }

    static let appBundle = Bundle(for: AppCoordinator.self)
    static let embedder: OnDeviceEmbedder? = OnDeviceEmbedder(bundle: appBundle)
    static let marcusID = UUID()
    static let threshold: Float = 0.40
    static var gallery: Gallery?
    static var sameScores: [Float] = []
    static var diffScores: [Float] = []

    override func setUp() async throws {
        try XCTSkipIf(Self.embedder == nil, "w600k_mbf.onnx not bundled")
        if Self.gallery == nil { Self.gallery = try await enroll() }
    }

    struct Run { var events: [PerceptionEvent]; var pipeline: PerceptionPipeline; var duration: Double }

    func run(_ clip: String, gallery: Gallery, burstAll: Bool = false, tail: Double = 0.8) async throws -> Run {
        guard let src = VideoFileFrameSource(fixtureNamed: clip, bundle: Self.appBundle),
              let url = Self.appBundle.url(forResource: clip, withExtension: "mp4") else { throw XCTSkip("\(clip).mp4 missing; skipping") }
        src.loops = false
        let duration = try await CMTimeGetSeconds(AVURLAsset(url: url).load(.duration))
        let provider = StaticGallery(gallery)
        let p = PerceptionFactory.make(embedder: Self.embedder!, threshold: Self.threshold)
        let box = Box<(t: Double, e: PerceptionEvent)>()
        let stream = p.subscribe()
        let t0 = CACurrentMediaTime()
        let collector = Task { for await e in stream { box.add((CACurrentMediaTime() - t0, e)) } }
        try await p.start(frames: src, gallery: provider)
        try await src.start()
        let deadline = CACurrentMediaTime() + duration + tail
        while CACurrentMediaTime() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
            if burstAll { for t in p.currentTracks() { p.requestBurst(track: t.trackID, seconds: 10) } }
        }
        src.stop(); p.stop()
        _ = await collector.value
        _ = provider
        let timed = box.items.filter { if case .snapshot = $0.e { return false }; return true }
        let kinds = timed.map(\.e)
        print("[fixture] \(clip): \(String(format: "%.1f", duration)) s, frames=\(p.stats.framesProcessed) embeds=\(p.stats.embeddings) " +
              "detect≈\(String(format: "%.0f", p.stats.detectMillis)) ms embed≈\(String(format: "%.0f", p.stats.embedMillis)) ms events=\(timed.map { String(format: "%.1fs ", $0.t) + $0.e.kindName + ($0.e.personName.map { "(\($0))" } ?? "") })")
        return Run(events: kinds, pipeline: p, duration: duration)
    }

    func enroll() async throws -> Gallery {
        let empty = Gallery(modelID: "w600k_mbf", people: [])
        let r = try await run("enroll_marcus", gallery: empty, burstAll: true)
        let tracks = r.pipeline.currentTracks()
        let trackID = try XCTUnwrap(tracks.max(by: { $0.faceBox.height < $1.faceBox.height })?.trackID, "no face tracked during enrollment")
        let best = r.pipeline.bestEmbeddings(track: trackID, max: 8)
        XCTAssertGreaterThanOrEqual(best.count, 3, "expected several enrollment embeddings")
        XCTAssertTrue(best.allSatisfy { $0.thumbnailJPEG != nil })
        let vecs = best.map(\.vector)
        var self_: [Float] = []
        for i in 0..<vecs.count { for j in (i + 1)..<vecs.count { self_.append(Matcher.cosine(vecs[i], vecs[j])) } }
        print("[fixture] enrollment: \(best.count) embeddings kept (qualities \(best.map { String(format: "%.2f", $0.quality) })), pairwise cosine \(Self.describe(self_))")
        XCTAssertTrue(r.events.allSatisfy { !$0.kindName.hasPrefix("known") }, "nobody is known during enrollment")
        return Gallery(modelID: "w600k_mbf", people: [(Self.marcusID, "Marcus", vecs)])
    }

    static func describe(_ xs: [Float]) -> String {
        guard !xs.isEmpty else { return "n=0" }
        let s = xs.sorted()
        func q(_ f: Double) -> Float { s[min(s.count - 1, Int(Double(s.count - 1) * f))] }
        return String(format: "n=%d min %.2f p10 %.2f median %.2f p90 %.2f max %.2f", s.count, s[0], q(0.1), q(0.5), q(0.9), s[s.count - 1])
    }

    func record(_ r: Run, same: Bool) {
        let scores = r.pipeline.matchLog.map(\.bestScore)
        if same { Self.sameScores += scores } else { Self.diffScores += scores }
        print("[fixture] \(same ? "same-person" : "different-person") max-cosine per embedding: \(Self.describe(scores))")
    }

    func testApproachMarcusEmitsApproachingAndArrived() async throws {
        let r = try await run("approach_marcus", gallery: try XCTUnwrap(Self.gallery))
        record(r, same: true)
        let names = Set(r.events.compactMap(\.personName))
        XCTAssertEqual(names, ["Marcus"])
        let kinds = r.events.map(\.kindName)
        XCTAssertTrue(kinds.contains("knownAppeared"), "Marcus should be named: \(kinds)")
        XCTAssertTrue(kinds.contains("knownApproaching"), "approach not detected: \(kinds)")
        XCTAssertTrue(kinds.contains("knownArrived"), "arrival not detected in the 2.9 s clip: \(kinds)")
    }

    func testStrangersEmitNoKnownEvents() async throws {
        let r = try await run("strangers", gallery: try XCTUnwrap(Self.gallery))
        record(r, same: false)
        let known = r.events.filter { $0.kindName.hasPrefix("known") }
        XCTAssertTrue(known.isEmpty, "strangers were named: \(known.map(\.kindName))")
        XCTAssertTrue(r.events.contains { if case .unknownCountChanged(let n) = $0 { return n >= 1 }; return false }, "unknown people should be counted")
        XCTAssertGreaterThan(r.pipeline.matchLog.count, 5)
        XCTAssertLessThan(r.pipeline.matchLog.map(\.bestScore).max() ?? 0, Self.threshold)
    }

    func testMixedNamesOnlyMarcus() async throws {
        let r = try await run("mixed", gallery: try XCTUnwrap(Self.gallery))
        let names = Set(r.events.compactMap(\.personName))
        XCTAssertEqual(names, ["Marcus"], "only Marcus may be named: \(r.events.map { $0.kindName + "(" + ($0.personName ?? "-") + ")" })")
        let marcusTracks = Set(r.pipeline.matchLog.filter(\.accepted).map(\.trackID))
        let same = r.pipeline.matchLog.filter { marcusTracks.contains($0.trackID) }.map(\.bestScore)
        let diff = r.pipeline.matchLog.filter { !marcusTracks.contains($0.trackID) }.map(\.bestScore)
        Self.sameScores += same; Self.diffScores += diff
        print("[fixture] mixed: Marcus tracks \(marcusTracks.sorted()) same \(Self.describe(same)) others \(Self.describe(diff))")
        XCTAssertFalse(marcusTracks.isEmpty)
        XCTAssertTrue(r.events.contains { if case .unknownCountChanged(let n) = $0 { return n >= 1 }; return false })
    }

    func testLeaveMarcusEmitsLeft() async throws {
        let r = try await run("leave_marcus", gallery: try XCTUnwrap(Self.gallery), tail: 1.0)
        record(r, same: true)
        XCTAssertEqual(Set(r.events.compactMap(\.personName)), ["Marcus"])
        XCTAssertTrue(r.events.map(\.kindName).contains("knownLeft"), "left not emitted: \(r.events.map(\.kindName))")
    }

    func testZZZ_CosineDistributionSummary() throws {
        print("[fixture] SAME-PERSON  \(Self.describe(Self.sameScores))")
        print("[fixture] DIFFERENT    \(Self.describe(Self.diffScores))  threshold \(Self.threshold) margin \(MatcherConfig.default.margin)")
        if let e = Self.embedder { print(String(format: "[fixture] embedder %@ avg %.1f ms over %d embeddings", "\(e.provider)", e.averageMillis, e.count)) }
    }

    func testMissingFixturesAreSkipped() async throws {
        XCTAssertNil(VideoFileFrameSource(fixtureNamed: "no_reply", bundle: Self.appBundle))
        XCTAssertNil(VideoFileFrameSource(fixtureNamed: "distance_calibration", bundle: Self.appBundle))
    }
}
