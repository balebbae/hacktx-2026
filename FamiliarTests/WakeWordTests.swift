import XCTest
@testable import Familiar

final class WakeWordTests: XCTestCase {
    func testFindExactAndFuzzy() {
        XCTAssertEqual(WakeWord.find(in: "hey Poyo, who's here?"), "who's here")
        XCTAssertEqual(WakeWord.find(in: "poyo call marcus"), "call marcus")
        XCTAssertEqual(WakeWord.find(in: "Pollo, what's in front of me"), "what's in front of me")
        XCTAssertEqual(WakeWord.find(in: "boyo mute"), "mute")
        XCTAssertEqual(WakeWord.find(in: "po yo who is around"), "who is around")
        XCTAssertEqual(WakeWord.find(in: "poyo's quiet mode"), "quiet mode")
        XCTAssertEqual(WakeWord.find(in: "okay poyo"), "")
        XCTAssertEqual(WakeWord.find(in: "so I told them poyo is great"), "is great", "exact name counts anywhere")
        XCTAssertEqual(WakeWord.find(in: "Can you save him to my contacts, Poyo?"), "can you save him to my contacts", "name at the end: the request is before it")
        XCTAssertEqual(WakeWord.find(in: "Hey, what's in front of me, Poyo?"), "what's in front of me")
        XCTAssertEqual(WakeWord.find(in: "hey poyo"), "")
        XCTAssertNil(WakeWord.find(in: "I like the pollo asado at that place"), "aliases only near the start")
        XCTAssertNil(WakeWord.find(in: "my family is here"))
        XCTAssertNil(WakeWord.find(in: "nice meeting you marcus"))
        XCTAssertNil(WakeWord.find(in: "the body of the post"))
        XCTAssertNil(WakeWord.find(in: ""))
    }

    func testLevenshtein() {
        XCTAssertEqual(WakeWord.levenshtein("poyo", "poyo"), 0)
        XCTAssertEqual(WakeWord.levenshtein("poyo", "pojo"), 1)
        XCTAssertEqual(WakeWord.levenshtein("poyo", "body"), 3)
        XCTAssertEqual(WakeWord.levenshtein("", "abc"), 3)
    }

    func testFinalWithCommandHitsImmediately() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "Poyo, who's here?", isFinal: true, t: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.command, .whoIsHere)
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testRequestBeforeTheNameHitsImmediately() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "Can you save him to my contacts, Poyo?", isFinal: true, t: 10)
        XCTAssertEqual(hits.map(\.command), [.rememberThem])
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testFinalWithAQuestionHitsImmediatelyEvenUnparsed() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "Poyo, read that sign for me", isFinal: true, t: 10)
        XCTAssertEqual(hits.map(\.text), ["read that sign for me"])
        XCTAssertNil(hits.first?.command)
    }

    func testVolatileTextEmitsOnceSettledAndItsFinalIsSwallowed() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo", isFinal: false, t: 10)
        XCTAssertTrue(ww.isListeningForCommand)
        ww.feed(text: "poyo call", isFinal: false, t: 10.4)
        ww.feed(text: "poyo call marcus", isFinal: false, t: 10.8)
        ww.tick(now: 11.2)
        XCTAssertEqual(hits.count, 0, "still changing")
        ww.tick(now: 11.9)
        XCTAssertEqual(hits.map(\.command), [.call("Marcus")])
        ww.feed(text: "poyo call marcus please", isFinal: false, t: 12)
        ww.feed(text: "Poyo, call Marcus please.", isFinal: true, t: 12.3)
        XCTAssertEqual(hits.count, 1, "the same utterance does not fire twice")
        XCTAssertFalse(ww.isListeningForCommand)
        ww.feed(text: "Poyo, who's here?", isFinal: true, t: 20)
        XCTAssertEqual(hits.count, 2)
    }

    func testSpeechEndpointFlushesTheRequestSooner() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo what's", isFinal: false, t: 10)
        ww.feed(text: "poyo what's on the table", isFinal: false, t: 10.6)
        ww.endpoint(at: 10.7)                                   // the detector: speech stopped
        ww.tick(now: 10.8)
        XCTAssertEqual(hits.count, 0, "the text must hold still for a beat after speech stops")
        ww.tick(now: 10.9)
        XCTAssertEqual(hits.map(\.text), ["what's on the table"], "0.25 s after the last change instead of 0.5")
        ww.feed(text: "Poyo, what's on the table?", isFinal: true, t: 11.8)
        XCTAssertEqual(hits.count, 1, "its final is swallowed")
        // Speech that resumed well after an endpoint makes that endpoint stale: the full settle applies again.
        ww.feed(text: "poyo call", isFinal: false, t: 20)
        ww.endpoint(at: 20.1)
        ww.feed(text: "poyo call marcus", isFinal: false, t: 21)
        ww.tick(now: 21.3)
        XCTAssertEqual(hits.count, 1, "0.3 s after a change: not settled")
        ww.tick(now: 21.6)
        XCTAssertEqual(hits.last?.command, .call("Marcus"))
        ww.endpoint(at: 30)
        ww.tick(now: 30.5)
        XCTAssertEqual(hits.count, 2, "an endpoint with nothing pending is nothing")
    }

    func testACutOffRequestWaitsAndItsFinalCorrectsIt() {
        // Device log 08:20:49: "Hey Poyo, can you … update his name?" went out as "can you" after a pause.
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "hey poyo can you", isFinal: false, t: 10)
        ww.endpoint(at: 10.1)
        ww.tick(now: 10.6)
        XCTAssertEqual(hits.count, 0, "'can you' promises more: not at 0.5 s, endpoint or not")
        ww.tick(now: 11.6)
        XCTAssertEqual(hits.map(\.text), ["can you"], "but it does go out after 1.5 s of silence")
        XCTAssertFalse(hits[0].isCorrection)
        ww.feed(text: "Hey Poyo, can you update his name?", isFinal: true, t: 13.5)
        XCTAssertEqual(hits.map(\.text), ["can you", "can you update his name"], "the final said more: a correction supersedes the early hit")
        XCTAssertTrue(hits[1].isCorrection)
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testAFinalThatSaysNothingMoreIsSwallowedAndCommandsAreNotRepeated() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo what's on the table", isFinal: false, t: 10)
        ww.tick(now: 10.6)
        XCTAssertEqual(hits.map(\.text), ["what's on the table"])
        ww.feed(text: "Poyo, what's on the table?", isFinal: true, t: 12)
        XCTAssertEqual(hits.count, 1, "same words: swallowed")
        ww.feed(text: "poyo quiet mode", isFinal: false, t: 20)
        ww.tick(now: 20.6)
        XCTAssertEqual(hits.last?.command, .setMode(.quiet))
        ww.feed(text: "Poyo, quiet mode please.", isFinal: true, t: 22)
        XCTAssertEqual(hits.count, 2, "the fuller final parses to the same command: no second 'Quiet mode.'")
    }

    func testLooksComplete() {
        for s in ["what's on the table", "read that sign", "who's here", "mute", "is there a door", "which side is the door"] {
            XCTAssertTrue(WakeWord.looksComplete(s), s)
        }
        for s in ["can you", "change to", "changed", "what was that i", "where is my", "um", "tell me about the", "hey"] {
            XCTAssertFalse(WakeWord.looksComplete(s), s)
        }
    }

    func testRepeatedWakeWordIsOneWakeWord() {
        XCTAssertEqual(WakeWord.find(in: "Poyo, Poyo, who's here?"), "who's here")
        XCTAssertEqual(WakeWord.find(in: "poyo poyo"), "")
        XCTAssertEqual(WakeWord.find(in: "Pollo poyo can you update his name"), "can you update his name")
    }

    func testALongRequestIsNotCutAtTheCollectWindow() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo can you", isFinal: false, t: 10)
        ww.feed(text: "poyo can you update his", isFinal: false, t: 12)
        ww.feed(text: "poyo can you update his name to", isFinal: false, t: 14.2)
        ww.tick(now: 14.5)
        XCTAssertEqual(hits.count, 0, "4.5 s after the wake word but still being said")
        ww.feed(text: "poyo can you update his name to sanjay", isFinal: false, t: 15)
        ww.tick(now: 15.6)
        XCTAssertEqual(hits.map(\.text), ["can you update his name to sanjay"])
        ww.feed(text: "poyo", isFinal: false, t: 30)
        ww.feed(text: "poyo tell me", isFinal: false, t: 37)
        ww.tick(now: 38.1)
        XCTAssertEqual(hits.count, 2, "nothing waits past 8 s")
    }

    func testBareWakeWordWaitsForTheNextFinal() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "Poyo.", isFinal: true, t: 10)
        XCTAssertTrue(ww.isListeningForCommand)
        ww.tick(now: 11)
        XCTAssertEqual(hits.count, 0)
        ww.feed(text: "what's on the table", isFinal: true, t: 12)
        XCTAssertEqual(hits.map(\.text), ["what's on the table"])
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testBareWakeWordFlushesAfterWindow() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo", isFinal: true, t: 10)
        ww.tick(now: 13)
        XCTAssertEqual(hits.count, 0)
        ww.tick(now: 14.5)
        XCTAssertEqual(hits.count, 1)
        XCTAssertNil(hits.first?.command)
        XCTAssertFalse(ww.isListeningForCommand)
    }

    func testLateFinalAfterWindowFlushes() {
        let ww = WakeWord()
        var hits: [WakeWordHit] = []
        ww.onHit = { hits.append($0) }
        ww.feed(text: "poyo", isFinal: true, t: 10)
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
        let transcriber = FakeTranscriber(text: "other: Hi, I'm Marcus.\nuser: Poyo, quiet mode.\nuser: Poyo, call Marcus.", interval: 0.02)
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
