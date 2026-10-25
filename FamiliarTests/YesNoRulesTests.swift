import XCTest
@testable import Familiar

final class YesNoRulesTests: XCTestCase {
    func testYes() {
        for r in ["Yes, sure.", "yeah", "Sure thing", "of course", "okay", "ok", "go ahead", "that's fine", "absolutely", "yep", "fine by me", "sounds good"] {
            XCTAssertEqual(RulesYesNoClassifier.classify(r), .yes, r)
        }
    }
    func testNo() {
        for r in ["Nah, I'm good.", "no", "No thanks", "I'd rather not", "not really", "nope", "please don't", "I don't think so"] {
            XCTAssertEqual(RulesYesNoClassifier.classify(r), .no, r)
        }
    }
    func testUnclear() {
        for r in ["what do you mean", "hmm", "", "what are you building", "maybe later"] {
            XCTAssertEqual(RulesYesNoClassifier.classify(r), .unclear, r)
        }
    }
    func testFixtures() throws {
        let b = Bundle(for: AppCoordinator.self)
        let yes = try String(contentsOf: XCTUnwrap(b.url(forResource: "yes_reply", withExtension: "txt")), encoding: .utf8)
        let no = try String(contentsOf: XCTUnwrap(b.url(forResource: "no_reply", withExtension: "txt")), encoding: .utf8)
        XCTAssertEqual(RulesYesNoClassifier.classify(FakeTranscriber.parse(yes).last(where: { $0.speaker == .other })?.text ?? ""), .yes)
        XCTAssertEqual(RulesYesNoClassifier.classify(FakeTranscriber.parse(no).last(where: { $0.speaker == .other })?.text ?? ""), .no)
    }
    func testCompositeFallsThroughOnUnclear() async {
        struct AlwaysNo: YesNoClassifier { func classify(_ reply: String) async -> YesNo { .no } }
        let c = CompositeYesNoClassifier(rules: RulesYesNoClassifier(), foundationModels: nil, meta: AlwaysNo(), timeout: 1)
        let a = await c.classify("Yes, sure."); XCTAssertEqual(a, .yes)
        let b = await c.classify("I would prefer you forget my face"); XCTAssertEqual(b, .no)
    }
}
