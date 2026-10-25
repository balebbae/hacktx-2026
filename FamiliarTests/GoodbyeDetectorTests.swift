import XCTest
@testable import Familiar

final class GoodbyeDetectorTests: XCTestCase {
    func testPhrases() {
        for s in ["Nice meeting you, Marcus!", "well, see you around", "take care", "it was great meeting you", "okay bye bye", "catch you later", "Good to meet you."] {
            XCTAssertTrue(GoodbyeDetector.isGoodbye(s), s)
        }
        for s in ["I'm Marcus", "where are you from", "see", "nice", "familiar who's here", "I'll take the salad"] {
            XCTAssertFalse(GoodbyeDetector.isGoodbye(s), s)
        }
    }

    func testFeedPublishesSignal() async {
        let d = GoodbyeDetector()
        let stream = d.subscribe()
        var times: [TimeInterval] = []
        d.onGoodbye = { times.append($0) }
        XCTAssertFalse(d.feed(TranscriptSegment(text: "hello", start: 1, end: 2, isFinal: true, speaker: .other)))
        XCTAssertFalse(d.feed(TranscriptSegment(text: "see you", start: 3, end: 4, isFinal: false, speaker: .other)), "volatile text ignored")
        XCTAssertTrue(d.feed(TranscriptSegment(text: "see you", start: 3, end: 4, isFinal: true, speaker: .other)))
        XCTAssertEqual(times, [4])
        var got: SpeechSignal?
        for await s in stream { got = s; break }
        XCTAssertEqual(got, .goodbyeDetected(t: 4))
    }

    func testDetectsFromFakeTranscriber() async throws {
        let transcriber = FakeTranscriber(text: "other: Hi, I'm Marcus.\nuser: Nice meeting you Marcus.", interval: 0.01)
        let d = SpeechFactory.makeGoodbyeDetector(transcriber: transcriber)
        let stream = d.subscribe()
        try await transcriber.start(audio: SilentAudioInput())
        var got: SpeechSignal?
        for await s in stream { got = s; break }
        transcriber.stop(); d.detach()
        if case .goodbyeDetected = got {} else { XCTFail("expected goodbye, got \(String(describing: got))") }
    }
}
