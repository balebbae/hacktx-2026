import XCTest
@testable import Familiar

final class ActionCaptionerTests: XCTestCase {
    private func face(_ id: Int, x: Double, name: String? = nil, distance: Distance = .medium, facing: Bool = false, mouth: Double? = nil) -> TrackSnapshot {
        TrackSnapshot(trackID: id, identity: name.map { .known(personID: UUID(), name: $0, score: 0.8) } ?? .unknown(bestScore: nil),
                      bearing: Spatial.bearing(centerX: x, hFOV: 53), distance: distance, faceBox: CGRect(x: x - 0.03, y: 0.15, width: 0.06, height: 0.08),
                      faceHeightPx: 80, yawDegrees: 0, isFacingUser: facing, mouthOpenness: mouth, quality: 0.9, timestamp: 0)
    }

    /// A 0.8-tall body (about 3 m away) whose centre is at `x`.
    private func body(x: Double, height: Double = 0.8) -> CGRect { CGRect(x: x - 0.1, y: 0.1, width: 0.2, height: height) }

    /// Runs passes at 4 Hz for `seconds`; returns every caption.
    private func run(_ c: inout ActionCaptioner, seconds: Double, pan: Double = 0, speech: Bool = false,
                     bodies: (Double) -> [CGRect] = { _ in [] }, faces: (Double) -> [TrackSnapshot] = { _ in [] }) -> [ActionCaption] {
        stride(from: 0.0, through: seconds, by: 0.25).compactMap { t in
            c.update(bodies: bodies(t), faces: faces(t), panRate: pan, speech: speech, now: 100 + t, hFOV: 53, vFOV: 40)
        }
    }

    func testCrossingLeftToRightIsSaidOnce() {
        var c = ActionCaptioner()
        let out = run(&c, seconds: 2, bodies: { t in [self.body(x: 0.15 + 0.35 * t)] })
        XCTAssertEqual(out, [.crossing(name: nil, leftToRight: true, distance: .medium, fast: false)])
        XCTAssertEqual(out.first?.text, "Someone crossing, left to right.")
        XCTAssertNotNil(c.recentText(now: 102))
    }

    func testHeadTurnIsNotACrossing() {
        var c = ActionCaptioner()
        // Head turning left at 20°/s: a person standing still slides right across the view at the same rate.
        func x(degrees: Double) -> Double { 0.5 + tan(degrees * .pi / 180) / (2 * tan(26.5 * .pi / 180)) }
        let out = run(&c, seconds: 2, pan: -20, bodies: { t in [self.body(x: x(degrees: 20 * t - 15))] })
        XCTAssertEqual(out, [])
    }

    func testFastHeadTurnSilencesCrossings() {
        var c = ActionCaptioner()
        XCTAssertEqual(run(&c, seconds: 2, pan: 45, bodies: { t in [self.body(x: 0.15 + 0.35 * t)] }), [])
    }

    func testKnownFaceInsideTheBodyNamesTheCrossing() {
        var c = ActionCaptioner()
        let out = run(&c, seconds: 2, bodies: { t in [self.body(x: 0.85 - 0.35 * t)] }, faces: { t in [self.face(1, x: 0.85 - 0.35 * t, name: "Marcus")] })
        XCTAssertEqual(out.first?.text, "Marcus crossing, right to left.")
    }

    func testClosestCrossingComesFirst() {
        var c = ActionCaptioner()
        let out = run(&c, seconds: 1, bodies: { t in [self.body(x: 0.1 + 0.35 * t, height: 0.3), self.body(x: 0.9 - 0.35 * t)] })
        XCTAssertEqual(out.first, .crossing(name: nil, leftToRight: false, distance: .medium, fast: false))
    }

    func testUnknownWalkingAway() {
        var c = ActionCaptioner()
        let out = run(&c, seconds: 2, bodies: { t in [self.body(x: 0.7, height: 0.8 - 0.15 * t)] })
        XCTAssertEqual(out.first?.text, "Someone walking away, 12 o'clock.")
    }

    func testGroupTalkingAmongThemselves() {
        var c = ActionCaptioner()
        let faces = { (_: Double) in [self.face(1, x: 0.4), self.face(2, x: 0.5), self.face(3, x: 0.6, name: "Priya")] }
        let out = run(&c, seconds: 5, speech: true, faces: faces)
        XCTAssertEqual(out.map(\.text), ["Priya and two others talking, 12 o'clock."], "said once, after it held 3 s")
    }

    func testGroupFacingTheWearerIsTheirOwnConversation() {
        var c = ActionCaptioner()
        let out = run(&c, seconds: 5, speech: true, faces: { _ in [self.face(1, x: 0.4, facing: true), self.face(2, x: 0.6, facing: true)] })
        XCTAssertEqual(out, [])
    }

    func testTwoPeopleCloseSideBySideTalking() {
        // 1 m away and 33° apart (about 0.6 m side by side): the old 20° rule never grouped people this close.
        var c = ActionCaptioner()
        let talking = { (t: Double) in Int(t * 4) % 2 == 0 ? 0.0 : 0.12 }
        let out = run(&c, seconds: 5, faces: { t in [self.face(1, x: 0.2, distance: .close, mouth: talking(t)), self.face(2, x: 0.8, distance: .close, mouth: 0.02)] })
        XCTAssertEqual(out.map(\.text), ["Two people talking together, 12 o'clock."])
    }

    func testStillMouthsAreNotTalkingEvenInANoisyRoom() {
        var c = ActionCaptioner()
        XCTAssertEqual(run(&c, seconds: 5, speech: true, faces: { _ in [self.face(1, x: 0.4, mouth: 0.03), self.face(2, x: 0.6, mouth: 0.03)] }), [])
    }

    func testGroupSurvivesDetectionFlicker() {
        var c = ActionCaptioner()
        // Every third pass one face is missing (turned away): the hold carries on and the group is said once.
        let out = run(&c, seconds: 6, speech: true, faces: { t in
            Int(t * 4) % 3 == 0 ? [self.face(1, x: 0.4)] : [self.face(1, x: 0.4), self.face(2, x: 0.55), self.face(3, x: 0.65)]
        })
        XCTAssertEqual(out.count, 1)
    }

    func testFarGroupsAreNotCaptioned() {
        var c = ActionCaptioner()
        XCTAssertEqual(run(&c, seconds: 5, speech: true, faces: { _ in [self.face(1, x: 0.45, distance: .far), self.face(2, x: 0.55, distance: .far)] }), [])
    }

    func testUtteranceGating() {
        let closeCrossing = ActionCaption.crossing(name: nil, leftToRight: true, distance: .close, fast: false)
        let group = ActionCaption.group(count: 2, names: [], hour: 1, distance: .medium, talking: true)
        let far = ActionCaption.walkingAway(hour: 12, distance: .far)
        func u(_ c: ActionCaption, _ mode: ChatterMode, moving: Bool = false, talk: Bool = false, gap: Bool = true, since: TimeInterval = 60) -> Utterance? {
            ActionCaption.utterance(for: c, mode: mode, moving: moving, inConversation: talk, inDialogueGap: gap, sinceLast: since)
        }
        XCTAssertEqual(u(closeCrossing, .quiet, moving: true, talk: true, gap: false, since: 0)?.priority, 1, "collision cue: always")
        XCTAssertNil(u(closeCrossing, .quiet))
        XCTAssertEqual(u(closeCrossing, .normal)?.priority, 2)
        XCTAssertNil(u(group, .normal, gap: false), "waits for a pause in the dialogue")
        XCTAssertNotNil(u(group, .normal, talk: true), "groups are about talking")
        XCTAssertNil(u(closeCrossing, .normal, talk: true))
        XCTAssertNil(u(group, .normal, since: 10))
        XCTAssertNotNil(u(group, .chatty, since: 10))
        XCTAssertNil(u(far, .normal))
        XCTAssertNotNil(u(far, .chatty))
    }

    func testPhrases() {
        let lines = [
            Phrasebook.action(.crossing(name: nil, leftToRight: false, distance: .close, fast: true)),
            Phrasebook.action(.walkingAway(hour: 1, distance: .medium)),
            Phrasebook.action(.group(count: 2, names: [], hour: 1, distance: .medium, talking: false)),
            Phrasebook.action(.group(count: 3, names: [], hour: 11, distance: .medium, talking: true)),
            Phrasebook.action(.group(count: 2, names: ["Marcus", "Priya"], hour: 12, distance: .close, talking: true)),
        ]
        XCTAssertEqual(lines, ["Someone hurrying past, right to left, close.", "Someone walking away, 1 o'clock.", "Two people together, 1 o'clock.",
                               "Three people talking together, 11 o'clock.", "Marcus and Priya talking, 12 o'clock."])
        for s in lines + Phrasebook.actionAlertPhrases {
            XCTAssertFalse(s.lowercased().contains("poyo"), s)
            XCTAssertEqual(SpeechSanitizer.clean(s), s, "nothing a sanitizer would cut")
        }
    }
}
