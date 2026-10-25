import XCTest
@testable import Familiar

final class CueGateTests: XCTestCase {
    func testPriorityZeroAlwaysAdmitted() {
        let gate = CueGate(muted: true, consentActive: true, userSpeaking: true)
        XCTAssertTrue(gate.admit(.test("Saved.", priority: 0)))
        XCTAssertFalse(gate.admit(.test("Marcus left.", priority: 1)))
        XCTAssertFalse(gate.admit(.test("Someone close, ahead.", priority: 3)))
    }

    func testEachFlagBlocksLowPriority() {
        let gate = CueGate()
        XCTAssertTrue(gate.admit(.test("Marcus, ahead, close.")))
        gate.muted = true
        XCTAssertFalse(gate.admit(.test("Marcus, ahead, close.")))
        gate.muted = false
        gate.consentActive = true
        XCTAssertFalse(gate.admit(.test("Marcus, ahead, close.")))
        gate.consentActive = false
        gate.userSpeaking = true
        XCTAssertFalse(gate.admit(.test("Marcus, ahead, close.")))
        gate.userSpeaking = false
        XCTAssertTrue(gate.admit(.test("Marcus, ahead, close.")))
    }
}
