import XCTest
@testable import Familiar

final class CommandParserTests: XCTestCase {
    func testPositivePhrasings() {
        let cases: [(String, Command)] = [
            ("who's here", .whoIsHere), ("Who is around?", .whoIsHere), ("who is with me", .whoIsHere), ("anyone there", .whoIsHere), ("who do you see", .whoIsHere), ("Whos nearby", .whoIsHere),
            ("remember them", .rememberThem), ("remember him", .rememberThem), ("save her", .rememberThem), ("Remember this person.", .rememberThem), ("remember their face", .rememberThem), ("add this guy", .rememberThem),
            ("remember the person in front of me", .rememberThem), ("save their contact", .rememberThem), ("add my new friend", .rememberThem), ("remember who is in front of me", .rememberThem),
            ("quiet mode", .setMode(.quiet)), ("go quiet", .setMode(.quiet)), ("normal mode", .setMode(.normal)), ("switch to normal", .setMode(.normal)), ("Chatty mode please", .setMode(.chatty)), ("be chatty", .setMode(.chatty)),
            ("mute", .mute), ("stop talking", .mute), ("be quiet", .mute), ("hush", .mute),
            ("unmute", .unmute), ("talk again", .unmute), ("un mute", .unmute),
            ("call Marcus", .call("Marcus")), ("phone marcus please", .call("Marcus")), ("dial Sarah Lee", .call("Sarah Lee")), ("ring Marcus now", .call("Marcus")),
            ("text Marcus", .text("Marcus")), ("send a message to marcus", .text("Marcus")), ("message Priya", .text("Priya")),
            ("where is Marcus", .whereIs("Marcus")), ("where's marcus?", .whereIs("Marcus")), ("where did Marcus go", .whereIs("Marcus")),
            ("repeat that", .repeatLast), ("say that again", .repeatLast), ("come again", .repeatLast), ("what did you say", .repeatLast),
            ("what's around me", .describeSurroundings), ("What is in front of me?", .describeSurroundings), ("describe the room", .describeSurroundings), ("where am I", .describeSurroundings), ("what do you see", .describeSurroundings),
            ("cancel", .cancel), ("never mind", .cancel), ("forget it", .cancel), ("stop", .cancel),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(CommandParser.parse(text), expected, "\"\(text)\"")
        }
    }

    func testNegatives() {
        let negatives = ["", "   ", "the weather is nice today", "I'm Marcus, nice to meet you", "hello there", "what time is it", "remember to buy milk", "call", "text them", "I like this song", "we met at the conference", "so anyway"]
        for text in negatives {
            XCTAssertNil(CommandParser.parse(text), "\"\(text)\" should not be a command")
        }
    }

    func testNormalizeStripsPunctuationAndCase() {
        XCTAssertEqual(CommandParser.normalize("  Who’s  HERE?! "), "who's here")
        XCTAssertEqual(CommandParser.normalize("Call Marcus."), "call marcus")
    }

    func testPrecedenceMuteBeforeQuietMode() {
        XCTAssertEqual(CommandParser.parse("be quiet"), .mute)
        XCTAssertEqual(CommandParser.parse("quiet mode"), .setMode(.quiet))
        XCTAssertEqual(CommandParser.parse("stop talking"), .mute)
    }
}
