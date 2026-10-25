import XCTest
@testable import Familiar

final class MotionStateTests: XCTestCase {
    private func motion() -> (MotionState, () -> [String]) {
        let m = MotionState()
        var lines: [String] = []
        m.log = { lines.append($0) }
        return (m, { lines })
    }

    func testHoldingThePhoneWhileTalkingIsNotWalking() {
        let (m, log) = motion()
        for i in 0..<100 { m.noteAcceleration(i % 2 == 0 ? 0.1 : 0.04, at: Double(i) / 25) }
        XCTAssertFalse(m.isMoving(at: 4))
        XCTAssertEqual(log(), [])
    }

    func testWalkingWithThePhone() {
        let (m, log) = motion()
        for i in 0..<50 { m.noteAcceleration(i % 2 == 0 ? 0.3 : 0.1, at: Double(i) / 25) }
        XCTAssertTrue(m.isMoving(at: 2))
        XCTAssertFalse(m.isMoving(at: 4), "the hold runs out once the steps stop")
        XCTAssertEqual(log().count, 1, "logged once when walking starts")
        XCTAssertTrue(log()[0].hasPrefix("motion: walking (phone"))
    }

    func testNoisyViewIsNotWalking() {
        // A seated conversation: flow divergence swings both ways around zero (nods, someone leaning in).
        let (m, _) = motion()
        for (i, rate) in [0.9, -0.8, 0.6, -0.7, 1.2, -0.9, 0.5, -0.6, 0.8, -1.0, 0.7, -0.5].enumerated() { m.noteExpansion(rate, at: Double(i) / 4) }
        XCTAssertFalse(m.isMoving(at: 3))
        // One big expansion (someone stepping up to the wearer) among still samples is not walking either.
        for (i, rate) in [0.0, 0.05, 2.5, 0.0, -0.05, 0.1, 0.0, 0.05].enumerated() { m.noteExpansion(rate, at: 10 + Double(i) / 4) }
        XCTAssertFalse(m.isMoving(at: 12))
    }

    func testSteadilyExpandingViewIsWalking() {
        let (m, log) = motion()
        for i in 0..<8 { m.noteExpansion(0.45 + (i % 2 == 0 ? 0.1 : -0.1), at: Double(i) / 4) }
        XCTAssertTrue(m.isMoving(at: 2))
        XCTAssertTrue(log().first?.hasPrefix("motion: walking (view") ?? false)
    }
}
