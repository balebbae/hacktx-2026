import XCTest
@testable import Familiar

final class WakeWordTests: XCTestCase {
    func testFindExactAndFuzzy() {
        XCTAssertEqual(WakeWord.find(in: "hey Familiar, who's here?"), "who's here")
        XCTAssertEqual(WakeWord.find(in: "familiar call marcus"), "call marcus")
        XCTAssertEqual(WakeWord.find(in: "familia who is around"), "who is around")
        XCTAssertEqual(WakeWord.find(in: "the miller who's here"), "who's here")
        XCTAssertEqual(WakeWord.find(in: "familier mute"), "mute")
        XCTAssertEqual(WakeWord.find(in: "familiar's quiet mode"), "quiet mode")
        XCTAssertEqual(WakeWord.find(in: "okay familiar"), "")
        XCTAssertNil(WakeWord.find(in: "my family is here"))
        XCTAssertNil(WakeWord.find(in: "nice meeting you marcus"))
        XCTAssertNil(WakeWord.find(in: ""))
    }

    func testLevenshtein() {
        XCTAssertEqual(WakeWord.levenshtein("familiar", "familiar"), 0)
        XCTAssertEqual(WakeWord.levenshtein("familiar", "familier"), 1)
        XCTAssertEqual(WakeWord.levenshtein("familiar", "family"), 3)
        XCTAssertEqual(WakeWord.levenshtein("", "abc"), 3)
    }

    func testFinalWithCommandHitsImmediately() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "Familiar, who's here?", isFinal: true, t: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.command, .whoIsHere)
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testCollectsFollowingTextWithinWindow() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "familiar", isFinal: false, t: 10)
        XCTAssertTrue(ww.isListeningForCommand)
        XCTAssertEqual(hits.count, 0)
        ww.feed(text: "familiar call", isFinal: false, t: 11)
        XCTAssertEqual(hits.count, 0, "volatile text never commits a command")
        ww.feed(text: "familiar call marcus", isFinal: true, t: 12)
        XCTAssertEqual(hits.map(\.command), [.call("Marcus")])
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testWindowFlushWithoutCommand() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "familiar", isFinal: true, t: 10)
        ww.feed(text: "um so", isFinal: true, t: 12)
        ww.tick(now: 13)
        XCTAssertEqual(hits.count, 0)
        ww.tick(now: 14.5)
        XCTAssertEqual(hits.count, 1)
        XCTAssertNil(hits.first?.command)
        XCTAssertEqual(hits.first?.text, "um so")
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testLateFinalAfterWindowFlushes() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "familiar", isFinal: true, t: 10)
        ww.feed(text: "something unrelated", isFinal: true, t: 20)
        XCTAssertEqual(hits.count, 1)
        XCTAssertNil(hits.first?.command)
    }

    func testIgnoresTextWithoutWakeWord() {
        let ww = WakeWord()
        var hits = 0
        ww.onHit = { _ in hits += 1 }
        ww.feed(text: "who's here", isFinal: true, t: 1)
        ww.feed(text: "call marcus", isFinal: true, t: 2)
        XCTAssertEqual(hits, 0)
    }

    func testCommandSourceFromFakeTranscriber() async throws {
        let transcriber = FakeTranscriber(text: "other: Hi, I'm Marcus.\nuser: Familiar, quiet mode.\nuser: Familiar, call Marcus.", interval: 0.02)
        let source = SpeechFactory.makeCommandSource(transcriber: transcriber)
        let stream = source.subscribe()
        try await transcriber.start(audio: SilentAudioInput())
        var got: [Command] = []
        for await c in stream { got.append(c); if got.count == 2 { break } }
        transcriber.stop()
        source.detach()
        XCTAssertEqual(got, [.setMode(.quiet), .call("Marcus")])
    }
}
