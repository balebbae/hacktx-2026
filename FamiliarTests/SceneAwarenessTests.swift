import XCTest
import CoreVideo
@testable import Familiar

/// `HazardPolicy` is the pure part of `SceneAwareness`; Vision itself only runs on the iPhone.
final class SceneAwarenessTests: XCTestCase {
    func testStairsNeedTwoOfThreeSightingsThenCoolDown() {
        var p = HazardPolicy()
        XCTAssertEqual(p.classify(["stairs": 0.8], now: 0), [])
        XCTAssertEqual(p.classify(["stairs": 0.7], now: 1), [.hazard(.stairs)])
        XCTAssertEqual(p.classify(["stairs": 0.9], now: 2), [], "cooldown")
        XCTAssertEqual(p.classify(["stairs": 0.9], now: 10), [.hazard(.stairs)])
    }

    func testWeakOrOneOffLabelsStaySilent() {
        var p = HazardPolicy()
        XCTAssertEqual(p.classify(["stairs": 0.3], now: 0), [])
        XCTAssertEqual(p.classify(["stairs": 0.45], now: 1), [])
        XCTAssertEqual(p.classify(["escalator": 0.9], now: 2), [])
        XCTAssertEqual(p.classify([:], now: 3), [])
    }

    func testLoomingNeedsConsecutiveShortTimeToContact() {
        var p = HazardPolicy()
        XCTAssertNil(p.flow(timeToContact: 0.8, now: 0))
        XCTAssertNil(p.flow(timeToContact: 5, now: 0.25))
        XCTAssertNil(p.flow(timeToContact: 0.9, now: 0.5))
        XCTAssertEqual(p.flow(timeToContact: 1.0, now: 0.75), .hazard(.obstacle))
        XCTAssertNil(p.flow(timeToContact: 0.5, now: 1.0), "cooldown")
        XCTAssertNil(p.flow(timeToContact: nil, now: 1.25))
    }

    func testPlaceAnnouncedOnceWhenStableAndPeopleNeverDescribed() {
        var p = HazardPolicy()
        let labels: [String: Float] = ["kitchen": 0.7, "table": 0.6, "chair": 0.5, "door": 0.4, "people": 0.9, "adult": 0.9, "clothing": 0.8, "hat": 0.7]
        XCTAssertEqual(p.classify(labels, now: 0), [])
        XCTAssertEqual(p.classify(labels, now: 6), [.placeChanged("kitchen")])
        XCTAssertEqual(p.classify(labels, now: 12), [])
        XCTAssertEqual(p.describe(now: 12), "Kitchen. Table, chair, door.")
        for word in ["people", "adult", "clothing", "hat"] { XCTAssertFalse(p.describe(now: 12).lowercased().contains(word), word) }
    }

    func testDescribeOrdersHazardsPeopleThenPlace() {
        var p = HazardPolicy()
        _ = p.classify(["stairs": 0.9, "library": 0.8], now: 0)
        _ = p.classify(["stairs": 0.9, "library": 0.8], now: 1)
        XCTAssertEqual(p.describe(now: 2, people: "Marcus, ahead, close. No one else."), "Stairs ahead. Marcus, ahead, close. No one else. Library.")
        XCTAssertEqual(p.describe(now: 30), "Library.", "a hazard not seen for 5 s is no longer reported")
        XCTAssertEqual(HazardPolicy().describe(now: 0), Phrasebook.nothingToName)
    }

    func testCentreDivergenceOfSyntheticExpansion() throws {
        // u = k(x − cx), v = k(y − cy) is a pure expansion with divergence 2k.
        let k: Float = 0.05, n = 64
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, n, n, kCVPixelFormatType_TwoComponent32Float, nil, &pb)
        let flow = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(flow, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(flow)), rowBytes = CVPixelBufferGetBytesPerRow(flow)
        for y in 0..<n {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<n { row[2 * x] = k * Float(x - n / 2); row[2 * x + 1] = k * Float(y - n / 2) }
        }
        CVPixelBufferUnlockBaseAddress(flow, [])
        XCTAssertEqual(SceneAwareness.centreDivergence(flow), Double(2 * k), accuracy: 1e-4)
    }

    func testHazardWordingIsShortAndWakeWordFree() {
        for k in HazardKind.allCases {
            let s = Phrasebook.hazard(k)
            XCTAssertLessThanOrEqual(s.split(separator: " ").count, 3, s)
            XCTAssertFalse(s.localizedCaseInsensitiveContains("familiar"))
        }
    }
}
