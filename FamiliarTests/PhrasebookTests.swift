import XCTest
@testable import Familiar

final class PhrasebookTests: XCTestCase {
    func testCueStrings() {
        XCTAssertEqual(Phrasebook.appeared(name: "Marcus", bearing: .atClock(12), distance: .close), "Marcus, 12 o'clock, close.")
        XCTAssertEqual(Phrasebook.appeared(name: "Marcus", bearing: .atClock(11), distance: .far), "Marcus, 11 o'clock, far.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .atClock(1)), "Marcus, coming from 1 o'clock.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .atClock(11)), "Marcus, coming from 11 o'clock.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .atClock(12)), "Marcus, coming toward you.")
        XCTAssertEqual(Phrasebook.arrived(name: "Marcus"), "Marcus, next to you.")
        XCTAssertEqual(Phrasebook.left(name: "Marcus"), "Marcus left.")
        XCTAssertEqual(Phrasebook.unknownClose(bearing: .atClock(11)), "Someone close, 11 o'clock.")
        XCTAssertEqual(Phrasebook.unknownClose(bearing: .atClock(12)), "Someone close, 12 o'clock.")
        XCTAssertEqual(Phrasebook.speaking(name: "Marcus"), "Marcus.")
    }

    func testRollCallStrings() {
        XCTAssertEqual(Phrasebook.rollCallOthers(count: 0), "No one else.")
        XCTAssertEqual(Phrasebook.rollCallOthers(count: 1), "One other person.")
        XCTAssertEqual(Phrasebook.rollCallOthers(count: 3), "3 other people.")
        XCTAssertEqual(Phrasebook.rollCallNoKnown(count: 3), "No one I know. 3 people.")
        XCTAssertEqual(Phrasebook.rollCallNoKnown(count: 0), "I don't see anyone.")
    }

    func testConsentAndCommandStrings() {
        XCTAssertEqual(Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"), "Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?")
        XCTAssertEqual(Phrasebook.consentQuestion(userName: "Priya", name: nil), "Priya would like to recognize you next time you meet. Okay to remember your face?")
        XCTAssertEqual(Phrasebook.saved(name: "Marcus"), "Saved. Marcus is in your contacts.")
        XCTAssertEqual(Phrasebook.calling(name: "Marcus"), "Calling Marcus.")
        XCTAssertEqual(Phrasebook.texting(name: "Marcus"), "Opening a message to Marcus.")
        XCTAssertEqual(Phrasebook.unknownPerson("Bob"), "I don't know anyone called Bob.")
        XCTAssertEqual(Phrasebook.notVisible(name: "Marcus"), "I don't see Marcus.")
        XCTAssertEqual(Phrasebook.mode(.chatty), "Chatty mode.")
    }

    func testNoPhraseContainsTheWakeWord() {
        let all = [Phrasebook.shouldIAdd, Phrasebook.lookTowardMe, Phrasebook.wasThatAYes, Phrasebook.whatShouldICallYou, Phrasebook.nothingSaved, Phrasebook.theyLeft, Phrasebook.muted, Phrasebook.unmuted, Phrasebook.didNotGetThat, Phrasebook.nobody, Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"), Phrasebook.saved(name: "Marcus")]
        for s in all { XCTAssertFalse(s.lowercased().contains("poyo"), s) }
    }

    func testClockFromTrueBearing() {
        func clock(_ deg: Double) -> Int { Bearing(degrees: deg, band: .ahead).clock }
        XCTAssertEqual(clock(0), 12)
        XCTAssertEqual(clock(14), 12)
        XCTAssertEqual(clock(-14), 12)
        XCTAssertEqual(clock(26.5), 1, "right edge of the 53° glasses view")
        XCTAssertEqual(clock(-26.5), 11, "left edge")
        XCTAssertEqual(clock(90), 3)
        XCTAssertEqual(clock(-90), 9)
        XCTAssertEqual(clock(180), 6)
        for h in 1...12 { XCTAssertEqual(Bearing.atClock(h).clock, h) }
    }

    func testPathAndHazardPhrases() {
        XCTAssertEqual(Phrasebook.pathAlert(what: "wall", bearing: .atClock(12), meters: 1.6), "Wall ahead, 2 meters.")
        XCTAssertEqual(Phrasebook.pathAlert(what: "chair", bearing: .atClock(1), meters: 0.7), "Chair, 1 o'clock, 1 meter.")
        XCTAssertEqual(Phrasebook.pathAlert(what: nil, bearing: .atClock(12), meters: nil), "Obstacle ahead.")
        XCTAssertEqual(Phrasebook.sceneHazard("stairs down", bearing: .atClock(11), meters: 3), "Stairs down, 11 o'clock, 3 meters.")
        XCTAssertEqual(Phrasebook.lastSeen(name: "Marcus", bearing: .atClock(1)), "I last saw Marcus at 1 o'clock.")
    }
}
