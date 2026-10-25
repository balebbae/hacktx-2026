import XCTest
@testable import Familiar

final class SpeakerQueueTests: XCTestCase {
    func makeSpeaker(hold: TimeInterval = 0, clock: ManualClock = ManualClock(), sleep: VoiceSpeaker.Sleep? = nil) -> (VoiceSpeaker, FakeSynth, FakePlayback) {
        let synth = FakeSynth()
        let playback = FakePlayback(clock: { clock.now })
        playback.holdSeconds = hold
        let speaker = VoiceSpeaker(synthesizer: synth, playback: playback, clock: { clock.now }, sleep: sleep ?? { _ in })
        return (speaker, synth, playback)
    }

    func testSpeaksAndReportsWindow() async {
        let clock = ManualClock(50)
        let (speaker, synth, playback) = makeSpeaker(clock: clock)
        let window = await speaker.speak(.test("Marcus, ahead, close."))
        XCTAssertEqual(window?.lowerBound, 50)
        XCTAssertEqual(window?.upperBound ?? 0, 50.65, accuracy: 0.001, "0.15 s lead-in + 0.5 s audio")
        XCTAssertEqual(synth.texts, ["Marcus, ahead, close."])
        XCTAssertEqual(playback.played.count, 1)
        XCTAssertEqual(speaker.spoken.map(\.utterance.text), ["Marcus, ahead, close."])
        XCTAssertFalse(speaker.isSpeaking)
    }

    func testQueueOrdersByPriorityThenFIFO() async {
        let (speaker, _, playback) = makeSpeaker(hold: 0.2)
        let a = Task { await speaker.speak(.test("A", priority: 3)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let b = Task { await speaker.speak(.test("B", priority: 2)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let c = Task { await speaker.speak(.test("C", priority: 1)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(speaker.queuedCount, 2)
        _ = await (a.value, b.value, c.value)
        XCTAssertEqual(playback.played.map(\.samples.count).count, 3)
        XCTAssertEqual(speaker.spoken.map(\.utterance.text), ["A", "C", "B"])
    }

    func testDedupeKeyReplacesQueued() async {
        let (speaker, _, _) = makeSpeaker(hold: 0.2)
        let a = Task { await speaker.speak(.test("A", priority: 3)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let b = Task { await speaker.speak(.test("Marcus, coming from your left.", priority: 1, dedupeKey: "move")) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let c = Task { await speaker.speak(.test("Marcus, next to you.", priority: 1, dedupeKey: "move")) }
        let bWindow = await b.value
        XCTAssertNil(bWindow, "replaced utterance resolves to nil")
        _ = await (a.value, c.value)
        XCTAssertEqual(speaker.spoken.map(\.utterance.text), ["A", "Marcus, next to you."])
    }

    func testQueueDepthTwoDropsLowestPriority() async {
        let (speaker, _, _) = makeSpeaker(hold: 0.2)
        var dropped: [String] = []
        speaker.onDropped = { u, why in dropped.append("\(u.text):\(why)") }
        let a = Task { await speaker.speak(.test("A", priority: 1)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let b = Task { await speaker.speak(.test("B", priority: 1)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let c = Task { await speaker.speak(.test("C", priority: 2)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let d = Task { await speaker.speak(.test("D", priority: 3)) }
        let dWindow = await d.value
        XCTAssertNil(dWindow)
        _ = await (a.value, b.value, c.value)
        XCTAssertEqual(speaker.spoken.map(\.utterance.text), ["A", "B", "C"])
        XCTAssertEqual(dropped, ["D:queue full"])
    }

    func testPriorityZeroInterruptsAndClearsQueue() async {
        let (speaker, _, playback) = makeSpeaker(hold: 0.4)
        let a = Task { await speaker.speak(.test("A", priority: 2)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let b = Task { await speaker.speak(.test("B", priority: 2)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(speaker.isSpeaking)
        let z = Task { await speaker.speak(.test("Saved. Marcus is in your contacts.", priority: 0)) }
        let aWindow = await a.value
        let bWindow = await b.value
        let zWindow = await z.value
        XCTAssertNil(aWindow, "cut off")
        XCTAssertNil(bWindow, "cleared")
        XCTAssertNotNil(zWindow)
        XCTAssertEqual(playback.stops, 1)
        XCTAssertEqual(playback.played.count, 2)
        XCTAssertEqual(speaker.spoken.filter { $0.window != nil }.map(\.utterance.text), ["Saved. Marcus is in your contacts."])
        XCTAssertFalse(speaker.isSpeaking)
    }

    func testSpacingBetweenLowPriorityCues() async {
        let clock = ManualClock(100)
        var waits: [TimeInterval] = []
        let (speaker, _, _) = makeSpeaker(clock: clock, sleep: { s in waits.append(s); clock.now += s })
        _ = await speaker.speak(.test("Marcus, ahead, close.", priority: 1))
        XCTAssertEqual(waits, [])
        clock.now = 101
        let second = await speaker.speak(.test("Priya, left, far.", priority: 1))
        XCTAssertEqual(waits.count, 1)
        XCTAssertEqual(waits.first ?? 0, 3.65, accuracy: 0.001, "last ended at 100.65, +4 s spacing")
        XCTAssertEqual(second?.lowerBound ?? 0, 104.65, accuracy: 0.001)
        _ = await speaker.speak(.test("Want to remember them?", priority: 0))
        XCTAssertEqual(waits.count, 1, "priority 0 never waits")
    }

    func testEarconAndLeadingSilence() async {
        let (speaker, _, playback) = makeSpeaker()
        _ = await speaker.speak(.test("Marcus, ahead, close.", earcon: true))
        _ = await speaker.speak(.test("Marcus.", earcon: false))
        let lead = Int(speaker.leadingSilence * 16_000)
        XCTAssertEqual(playback.played[0].samples.count, lead + Earcon.prefix(for: 16_000).count + 8_000)
        XCTAssertEqual(playback.played[1].samples.count, lead + 8_000)
        XCTAssertTrue(playback.played[0].samples.prefix(lead).allSatisfy { $0 == 0 })
        XCTAssertEqual(Earcon.samples.count, 1920)
        XCTAssertEqual(Earcon.samples.first, 0)
        XCTAssertGreaterThan(Earcon.samples.max() ?? 0, 0.3)
    }

    func testSynthesisFailureDropsUtterance() async {
        let (speaker, synth, playback) = makeSpeaker()
        synth.failTexts = ["boom"]
        var dropped: [String] = []
        speaker.onDropped = { u, _ in dropped.append(u.text) }
        let w = await speaker.speak(.test("boom"))
        XCTAssertNil(w)
        XCTAssertEqual(dropped, ["boom"])
        XCTAssertEqual(playback.played.count, 0)
    }

    func testFallbackSynthesizer() async throws {
        let primary = FakeSynth(id: "primary"); primary.failTexts = ["x"]
        let secondary = FakeSynth(id: "secondary")
        let fb = FallbackSynthesizer(primary: primary, fallback: secondary)
        var fell: [String] = []
        fb.onFallback = { text, _ in fell.append(text) }
        let ok = try await fb.synthesize("fine")
        XCTAssertEqual(ok.source, "primary")
        let fallen = try await fb.synthesize("x")
        XCTAssertEqual(fallen.source, "secondary")
        XCTAssertEqual(fell, ["x"])
        XCTAssertEqual(fb.id, "primary>secondary")
    }

    func testPrewarmSynthesizesEveryPhrase() async {
        let (speaker, synth, _) = makeSpeaker()
        let phrases = Phrasebook.prewarmSet(names: ["Marcus"])
        await speaker.prewarm(phrases)
        XCTAssertEqual(Set(synth.texts), Set(phrases))
    }

    func testStopAllClearsQueue() async {
        let (speaker, _, playback) = makeSpeaker(hold: 0.3)
        let a = Task { await speaker.speak(.test("A")) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let b = Task { await speaker.speak(.test("B", priority: 2)) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        speaker.stopAll()
        let (aw, bw) = await (a.value, b.value)
        XCTAssertNil(aw); XCTAssertNil(bw)
        XCTAssertEqual(playback.stops, 1)
        XCTAssertFalse(speaker.isSpeaking)
    }
}
