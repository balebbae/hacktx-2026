import XCTest
@testable import Familiar

final class FakeTranscriberTests: XCTestCase {
    final class Clock: @unchecked Sendable { var now: TimeInterval = 0 }

    func testParsesSpeakers() {
        let lines = FakeTranscriber.parse("user: Hi there!\nother: Hey, I'm Marcus.\n# comment\n\nsomething")
        XCTAssertEqual(lines, [.init(speaker: .user, text: "Hi there!"), .init(speaker: .other, text: "Hey, I'm Marcus."), .init(speaker: .none, text: "something")])
    }

    func testWindowTrimming() {
        let clock = Clock()
        let t = FakeTranscriber(text: "", clock: { clock.now })
        t.windowSeconds = 90
        clock.now = 10; t.emit(.init(speaker: .other, text: "one"))
        clock.now = 50; t.emit(.init(speaker: .other, text: "two"))
        clock.now = 120; t.emit(.init(speaker: .user, text: "three"))
        XCTAssertEqual(t.recentSegments(seconds: 90).map(\.text), ["two", "three"])
        XCTAssertEqual(t.recentSegments(seconds: 30).map(\.text), ["three"])
        XCTAssertEqual(t.recentSegments(seconds: 90).first?.speaker, .other)
    }

    func testEmitsLinesOnSchedule() async throws {
        let t = FakeTranscriber(text: "other: a\nuser: b", interval: 0.05)
        let stream = t.subscribe()
        try await t.start(audio: SilentAudioInput())
        var got: [String] = []
        for await s in stream { got.append(s.text); if got.count == 2 { break } }
        t.stop()
        XCTAssertEqual(got, ["a", "b"])
    }

    func testBundledConversationTranscriptLoads() throws {
        let t = try XCTUnwrap(FakeTranscriber(transcriptNamed: "conversation", bundle: Bundle(for: AppCoordinator.self)))
        XCTAssertEqual(t.lines.count, 8)
        XCTAssertTrue(t.lines.contains { $0.speaker == .other && $0.text.contains("I'm Marcus") })
    }
}
