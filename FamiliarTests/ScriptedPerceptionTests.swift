import XCTest
@testable import Familiar

final class ScriptedPerceptionTests: XCTestCase {
    final class Clock: @unchecked Sendable { var now: TimeInterval = 100 }

    func testEventsFireInOrderWithInjectedClock() async throws {
        let clock = Clock()
        let script = [
            ScriptEvent(t: 0.1, event: "unknownCountChanged", count: 2),
            ScriptEvent(t: 0.2, event: "knownAppeared", name: "Marcus", band: "farRight", distance: "far", trackID: 10),
            ScriptEvent(t: 0.3, event: "knownArrived", name: "Marcus", band: "ahead", distance: "close", trackID: 10),
            ScriptEvent(t: 0.4, event: "knownLeft", name: "Marcus"),
        ]
        let p = ScriptedPerception(events: script, clock: { clock.now }, snapshotInterval: 1000)
        p.loops = false
        let stream = p.subscribe()
        try await p.start(frames: SilentFrameSource(), gallery: InMemoryPeopleStore())
        var kinds: [String] = []
        let collector = Task {
            for await e in stream {
                if case .snapshot = e { continue }
                kinds.append(e.kindName)
                if kinds.count == 4 { break }
            }
        }
        for step in 1...5 {
            clock.now = 100 + Double(step) * 0.1 + 0.01
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        _ = await collector.value
        p.stop()
        XCTAssertEqual(kinds, ["unknownCountChanged", "knownAppeared", "knownArrived", "knownLeft"])
    }

    func testCurrentTracksAndIdentityAssignment() async throws {
        let clock = Clock()
        let p = ScriptedPerception(events: [ScriptEvent(t: 0, event: "unknownCountChanged", count: 2)], clock: { clock.now }, snapshotInterval: 1000)
        p.loops = false
        try await p.start(frames: SilentFrameSource(), gallery: InMemoryPeopleStore())
        try await Task.sleep(nanoseconds: 100_000_000)
        let tracks = p.currentTracks()
        XCTAssertEqual(tracks.count, 2)
        XCTAssertTrue(tracks.allSatisfy { !$0.identity.isKnown })
        let id = UUID()
        p.assignIdentity(track: tracks[0].trackID, personID: id, name: "Marcus")
        XCTAssertEqual(p.currentTracks().first { $0.trackID == tracks[0].trackID }?.identity.personID, id)
        let embs = p.bestEmbeddings(track: tracks[0].trackID, max: 5)
        XCTAssertEqual(embs.count, 3)
        XCTAssertEqual(embs[0].vector.count, 512)
        XCTAssertEqual(embs[0].modelID, "fake")
        XCTAssertNotNil(embs[0].thumbnailJPEG)
        XCTAssertEqual(sqrt(embs[0].vector.reduce(0) { $0 + $1 * $1 }), 1, accuracy: 0.001)
        p.stop()
    }

    func testBundledScriptDecodes() throws {
        let url = try XCTUnwrap(Bundle(for: AppCoordinator.self).url(forResource: "script", withExtension: "json"))
        let events = try JSONDecoder().decode([ScriptEvent].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(events.count, 8)
        XCTAssertEqual(events.map(\.t), events.map(\.t).sorted())
    }

    func testFixtureManifestDecodes() throws {
        let m = try XCTUnwrap(FixtureManifest.load(from: Bundle(for: AppCoordinator.self)))
        XCTAssertEqual(m.fov.horizontalDegrees, 53)
        XCTAssertEqual(m.clip(named: "enroll_marcus")?.person, "Marcus")
        XCTAssertEqual(m.clip(named: "yes_reply.mp4")?.expectYesNo, "yes")
    }
}
