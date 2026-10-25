import XCTest
@testable import Familiar

final class NameExtractorTests: XCTestCase {
    let x = RegexNameExtractor()

    func testStrongForms() async {
        for line in ["Hey, hi! I'm Marcus.", "I am Marcus.", "Hello, my name is Marcus and I build things"] {
            let g = await x.otherPersonName(segments: [seg(.other, line)], userName: "Priya")
            XCTAssertEqual(g.name, "Marcus", line); XCTAssertEqual(g.confidence, 0.9, accuracy: 0.001, line); XCTAssertEqual(g.source, "regex")
        }
    }

    func testWeakForms() async {
        for line in ["This is Marcus.", "It's Marcus.", "Call me Marcus.", "Marcus here."] {
            let g = await x.otherPersonName(segments: [seg(.other, line)], userName: "Priya")
            XCTAssertEqual(g.name, "Marcus", line); XCTAssertEqual(g.confidence, 0.7, accuracy: 0.001, line)
        }
    }

    func testIgnoresUserSegmentsAndUserName() async {
        let g = await x.otherPersonName(segments: [seg(.user, "I'm Priya."), seg(.other, "Nice to meet you, Priya.")], userName: "Priya")
        XCTAssertNil(g.name); XCTAssertEqual(g.confidence, 0)
        let g2 = await x.otherPersonName(segments: [seg(.other, "I'm Priya too actually")], userName: "Priya")
        XCTAssertNil(g2.name)
    }

    func testStopWordsNeverBecomeNames() async {
        for line in ["I'm Good.", "I'm Sorry.", "I'm Here.", "This is Great."] {
            let g = await x.otherPersonName(segments: [seg(.other, line)], userName: "Priya")
            XCTAssertNil(g.name, line)
        }
    }

    func testConversationFixture() async throws {
        let url = try XCTUnwrap(Bundle(for: AppCoordinator.self).url(forResource: "conversation", withExtension: "txt"))
        let lines = FakeTranscriber.parse(try String(contentsOf: url, encoding: .utf8))
        let segs = lines.map { seg($0.speaker, $0.text) }
        let g = await x.otherPersonName(segments: segs, userName: "Priya")
        XCTAssertEqual(g.name, "Marcus"); XCTAssertGreaterThanOrEqual(g.confidence, 0.9)
    }

    func testCompositeReturnsRegexWithoutCallingFallbacks() async {
        let slow = FixedName(guess: NameGuess(name: "Wrong", confidence: 1, source: "meta"))
        let c = CompositeNameExtractor(regex: RegexNameExtractor(), foundationModels: nil, meta: slow, overallTimeout: 1)
        let g = await c.otherPersonName(segments: [seg(.other, "I'm Marcus.")], userName: "Priya")
        XCTAssertEqual(g.name, "Marcus"); XCTAssertEqual(g.source, "regex")
    }

    func testCompositeFallsThroughToMetaAndNeverReturnsUserName() async {
        let meta = FixedName(guess: NameGuess(name: "Priya", confidence: 0.9, source: "meta"))
        let c = CompositeNameExtractor(regex: RegexNameExtractor(), foundationModels: nil, meta: meta, overallTimeout: 1)
        let g = await c.otherPersonName(segments: [seg(.other, "hello there")], userName: "Priya")
        XCTAssertNil(g.name)
        let meta2 = FixedName(guess: NameGuess(name: "Dana", confidence: 0.8, source: "meta"))
        let c2 = CompositeNameExtractor(regex: RegexNameExtractor(), foundationModels: nil, meta: meta2, overallTimeout: 1)
        let g2 = await c2.otherPersonName(segments: [seg(.other, "hello there")], userName: "Priya")
        XCTAssertEqual(g2.name, "Dana"); XCTAssertEqual(g2.source, "meta")
    }
}
