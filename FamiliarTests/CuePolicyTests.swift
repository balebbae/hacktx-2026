import XCTest
@testable import Familiar

final class CuePolicyTests: XCTestCase {
    let marcus = UUID()

    func testAppearedCueAndCooldown() {
        let policy = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, band: .farRight, distance: .far)
        let first = policy.utterances(for: .knownAppeared(t), mode: .normal, now: 10)
        XCTAssertEqual(first.map(\.text), ["Marcus, 1 o'clock, far."])
        XCTAssertEqual(first.first?.priority, 1)
        XCTAssertEqual(first.first?.personID, marcus)
        XCTAssertEqual(first.first?.earcon, true)
        XCTAssertEqual(policy.utterances(for: .knownAppeared(t), mode: .normal, now: 25), [])
        XCTAssertEqual(policy.utterances(for: .knownAppeared(t), mode: .normal, now: 41).count, 1)
    }

    func testQuietModeOnlyAppearedAndArrived() {
        let policy = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, band: .right, distance: .medium)
        XCTAssertEqual(policy.utterances(for: .knownAppeared(t), mode: .quiet, now: 1).count, 1)
        XCTAssertEqual(policy.utterances(for: .knownApproaching(t), mode: .quiet, now: 2), [])
        XCTAssertEqual(policy.utterances(for: .knownArrived(t), mode: .quiet, now: 3).map(\.text), ["Marcus, next to you."])
        XCTAssertEqual(policy.utterances(for: .speakingStarted(t), mode: .quiet, now: 4), [])
        XCTAssertEqual(policy.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: t.bearing), mode: .quiet, now: 5), [])
    }

    func testApproachingAndArrivedShareDedupeKey() {
        let policy = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, band: .left, distance: .medium)
        let approaching = policy.utterances(for: .knownApproaching(t), mode: .normal, now: 1)
        let arrived = policy.utterances(for: .knownArrived(t), mode: .normal, now: 2)
        XCTAssertEqual(approaching.map(\.text), ["Marcus, coming toward you."])
        XCTAssertEqual(arrived.map(\.text), ["Marcus, next to you."])
        XCTAssertEqual(approaching.first?.dedupeKey, arrived.first?.dedupeKey)
        // Approach right after an arrival is noise.
        XCTAssertEqual(policy.utterances(for: .knownApproaching(t), mode: .normal, now: 5), [])
    }

    func testLeftOnlySpokenAfterRecentClose() {
        let policy = FamiliarCuePolicy()
        let far = TestTracks.known("Marcus", id: marcus, band: .ahead, distance: .far)
        _ = policy.utterances(for: .knownAppeared(far), mode: .normal, now: 1)
        XCTAssertEqual(policy.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: far.bearing), mode: .normal, now: 5), [], "never close: no leave cue")
        _ = policy.utterances(for: .knownArrived(far), mode: .normal, now: 10)
        let left = policy.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: far.bearing), mode: .normal, now: 40)
        XCTAssertEqual(left.map(\.text), ["Marcus left."])
        XCTAssertEqual(left.first?.priority, 2)
        XCTAssertEqual(policy.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: far.bearing), mode: .normal, now: 41), [], "consumed")
        _ = policy.utterances(for: .knownArrived(far), mode: .normal, now: 100)
        XCTAssertEqual(policy.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: far.bearing), mode: .normal, now: 300), [], "close window expired")
    }

    func testSpeakingOncePerTrack() {
        let policy = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, track: 7)
        XCTAssertEqual(policy.utterances(for: .speakingStarted(t), mode: .normal, now: 1).map(\.text), ["Marcus."])
        XCTAssertEqual(policy.utterances(for: .speakingStarted(t), mode: .normal, now: 2), [])
        XCTAssertEqual(policy.utterances(for: .speakingStarted(TestTracks.unknown(track: 8)), mode: .chatty, now: 3), [])
    }

    func testUnknownCloseIsChattyOnly() {
        let policy = FamiliarCuePolicy()
        let stranger = TestTracks.unknown(track: 3, band: .left, distance: .close)
        XCTAssertEqual(policy.utterances(for: .snapshot(tracks: [stranger], preview: nil), mode: .normal, now: 1), [])
        let chatty = policy.utterances(for: .snapshot(tracks: [stranger], preview: nil), mode: .chatty, now: 2)
        XCTAssertEqual(chatty.map(\.text), ["Someone close, 12 o'clock."])
        XCTAssertEqual(chatty.first?.priority, 3)
        XCTAssertEqual(policy.utterances(for: .snapshot(tracks: [stranger], preview: nil), mode: .chatty, now: 10), [])
        XCTAssertEqual(policy.utterances(for: .snapshot(tracks: [TestTracks.unknown(track: 3, distance: .medium)], preview: nil), mode: .chatty, now: 30), [])
    }

    func testNeverNamesStrangersAndStaysShort() {
        let policy = FamiliarCuePolicy()
        let stranger = TestTracks.unknown(track: 3)
        for e: PerceptionEvent in [.knownAppeared(stranger), .knownApproaching(stranger), .knownArrived(stranger), .speakingStarted(stranger), .unknownCountChanged(3)] {
            XCTAssertEqual(policy.utterances(for: e, mode: .chatty, now: 1), [])
        }
        let p2 = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, band: .farLeft, distance: .medium)
        var all: [Utterance] = []
        all += p2.utterances(for: .knownAppeared(t), mode: .chatty, now: 1)
        all += p2.utterances(for: .knownApproaching(t), mode: .chatty, now: 2)
        all += p2.utterances(for: .knownArrived(t), mode: .chatty, now: 3)
        all += p2.utterances(for: .speakingStarted(t), mode: .chatty, now: 4)
        all += p2.utterances(for: .knownLeft(personID: marcus, name: "Marcus", last: t.bearing), mode: .chatty, now: 5)
        XCTAssertEqual(all.count, 5)
        for u in all {
            XCTAssertFalse(u.text.localizedCaseInsensitiveContains("familiar"))
            XCTAssertLessThanOrEqual(u.text.split(separator: " ").count, 6, u.text)
            XCTAssertEqual(u.audience, .user)
        }
    }

    func testPrewarmSetIsCleanVocabulary() {
        let set = Phrasebook.prewarmSet(names: ["Marcus", "Priya"])
        XCTAssertTrue(set.contains("Marcus, 12 o'clock, close."))
        XCTAssertTrue(set.contains("Priya left."))
        XCTAssertTrue(set.contains(Phrasebook.shouldIAdd))
        XCTAssertEqual(Set(set).count, set.count, "no duplicates")
        XCTAssertFalse(set.contains { $0.localizedCaseInsensitiveContains("familiar") })
        XCTAssertEqual(VoiceFactory.makeCuePolicy().cooldowns.appeared, 30)
    }
}
