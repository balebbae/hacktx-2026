import XCTest
@testable import Familiar

final class RollCallTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(RollCall.phrase(tracks: []), Phrasebook.nobody)
        let u = RollCall.utterance(tracks: [])
        XCTAssertEqual(u.priority, 0)
        XCTAssertEqual(u.text, Phrasebook.nobody)
    }

    func testOnlyStrangers() {
        let tracks = [TestTracks.unknown(track: 1, band: .left), TestTracks.unknown(track: 2, band: .right), TestTracks.unknown(track: 3)]
        XCTAssertEqual(RollCall.phrase(tracks: tracks), Phrasebook.rollCallNoKnown(count: 3))
        XCTAssertEqual(RollCall.phrase(tracks: [tracks[0]]), Phrasebook.rollCallNoKnown(count: 1))
    }

    func testKnownSortedLeftToRightThenOthers() {
        let marcus = UUID(), priya = UUID()
        let tracks = [
            TestTracks.known("Marcus", id: marcus, track: 1, band: .right, distance: .medium),
            TestTracks.unknown(track: 2, band: .ahead),
            TestTracks.known("Priya", id: priya, track: 3, band: .farLeft, distance: .close),
            TestTracks.unknown(track: 4, band: .farRight),
        ]
        XCTAssertEqual(RollCall.phrase(tracks: tracks), "Priya, far left, close. Marcus, right, medium. 2 other people.")
    }

    func testOneKnownOneOther() {
        let tracks = [TestTracks.known("Marcus", id: UUID(), track: 1), TestTracks.unknown(track: 2)]
        XCTAssertEqual(RollCall.phrase(tracks: tracks), "Marcus, ahead, close. One other person.")
        XCTAssertEqual(RollCall.phrase(tracks: [tracks[0]]), "Marcus, ahead, close. No one else.")
    }

    func testDuplicateKnownIdentityCountedOnce() {
        let marcus = UUID()
        let tracks = [TestTracks.known("Marcus", id: marcus, track: 1, band: .left), TestTracks.known("Marcus", id: marcus, track: 2, band: .right)]
        XCTAssertEqual(RollCall.phrase(tracks: tracks), "Marcus, left, close. One other person.")
    }

    func testNeverSaysFamiliar() {
        let tracks = [TestTracks.known("Marcus", id: UUID()), TestTracks.unknown(track: 2)]
        XCTAssertFalse(RollCall.phrase(tracks: tracks).localizedCaseInsensitiveContains("familiar"))
    }
}
