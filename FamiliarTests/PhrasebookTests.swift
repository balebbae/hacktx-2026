import XCTest
@testable import Familiar

final class PhrasebookTests: XCTestCase {
    func testCueStrings() {
        XCTAssertEqual(Phrasebook.appeared(name: "Marcus", band: .ahead, distance: .close), "Marcus, ahead, close.")
        XCTAssertEqual(Phrasebook.appeared(name: "Marcus", band: .farLeft, distance: .far), "Marcus, far left, far.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .right), "Marcus, coming from your right.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .farLeft), "Marcus, coming from your left.")
        XCTAssertEqual(Phrasebook.approaching(name: "Marcus", from: .ahead), "Marcus, coming toward you.")
        XCTAssertEqual(Phrasebook.arrived(name: "Marcus"), "Marcus, next to you.")
        XCTAssertEqual(Phrasebook.left(name: "Marcus"), "Marcus left.")
        XCTAssertEqual(Phrasebook.unknownClose(band: .left), "Someone close, on your left.")
        XCTAssertEqual(Phrasebook.unknownClose(band: .ahead), "Someone close, ahead.")
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
        for s in all { XCTAssertFalse(s.lowercased().contains("familiar"), s) }
    }
}
