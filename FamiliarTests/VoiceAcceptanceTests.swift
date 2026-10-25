import XCTest
@testable import Familiar

/// Scripted demo end to end: ScriptedPerception → FamiliarCuePolicy → CueGate → VoiceSpeaker, plus FakeTranscriber →
/// wake word → command → RollCall, all with injected clocks and no audio hardware.
final class VoiceAcceptanceTests: XCTestCase {
    let script = [
        ScriptEvent(t: 1, event: "unknownCountChanged", count: 3),
        ScriptEvent(t: 8, event: "knownAppeared", name: "Marcus", band: "farRight", distance: "far", trackID: 10),
        ScriptEvent(t: 13, event: "knownApproaching", name: "Marcus", band: "right", distance: "medium", trackID: 10),
        ScriptEvent(t: 18, event: "knownArrived", name: "Marcus", band: "ahead", distance: "close", trackID: 10),
        ScriptEvent(t: 24, event: "speakingStarted", name: "Marcus", band: "ahead", distance: "close", trackID: 10),
        ScriptEvent(t: 30, event: "unknownCountChanged", count: 1),
        ScriptEvent(t: 36, event: "knownLeft", name: "Marcus"),
        ScriptEvent(t: 48, event: "knownAppeared", name: "Marcus", band: "left", distance: "medium", trackID: 11),
        ScriptEvent(t: 54, event: "knownArrived", name: "Marcus", band: "ahead", distance: "close", trackID: 11),
        ScriptEvent(t: 60, event: "unknownCountChanged", count: 0),
    ]

    func testScriptedDemoSpeaksExpectedCues() async throws {
        let clock = ManualClock(100)
        let perception = ScriptedPerception(events: script, clock: { clock.now }, snapshotInterval: 1000)
        perception.loops = false
        let policy = VoiceFactory.makeCuePolicy()
        let gate = CueGate()
        let synth = FakeSynth()
        let playback = FakePlayback(clock: { clock.now })
        let speaker = VoiceSpeaker(synthesizer: synth, playback: playback, clock: { clock.now }, sleep: { _ in })
        let logLock = NSLock()
        var log: [String] = []
        speaker.onSpoken = { spoken in
            let line = "\(Int(spoken.window?.lowerBound ?? 0)) \(spoken.utterance.text)"
            logLock.lock(); log.append(line); logLock.unlock()
        }

        let events = perception.subscribe()
        try await perception.start(frames: SilentFrameSource(), gallery: InMemoryPeopleStore())
        let collector = Task {
            var seen = 0
            for await e in events {
                if case .snapshot = e { continue }
                seen += 1
                for u in policy.utterances(for: e, mode: .normal, now: clock.now) where gate.admit(u) {
                    await speaker.speak(u)
                }
                if seen == self.script.count { break }
            }
        }
        for step in 1...61 {
            clock.now = 100 + Double(step) + 0.01
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        collector.cancel()                      // AsyncStream iteration ends on cancellation
        _ = await collector.value
        perception.stop()
        speaker.onSpoken = nil
        logLock.lock(); let lines = log; logLock.unlock()

        XCTAssertEqual(speaker.spoken.map(\.utterance.text), [
            "Marcus, 1 o'clock, far.",
            "Marcus, coming toward you.",
            "Marcus, next to you.",
            "Marcus.",
            "Marcus left.",
            "Marcus, 12 o'clock, medium.",
            "Marcus, next to you.",
        ])
        print("[VoiceAcceptanceTests] spoken:\n" + lines.joined(separator: "\n"))
        XCTAssertFalse(speaker.spoken.contains { $0.utterance.text.localizedCaseInsensitiveContains("familiar") })
        XCTAssertFalse(speaker.spoken.contains { $0.utterance.text.localizedCaseInsensitiveContains("someone") }, "strangers are silent in normal mode")

        // Wake word → command → roll call over the final scene (Marcus close ahead, no strangers).
        let transcriber = FakeTranscriber(text: "other: Hi, I'm Marcus.\nuser: Poyo, who's here?", interval: 0.01)
        let commands = SpeechFactory.makeCommandSource(transcriber: transcriber)
        let stream = commands.subscribe()
        try await transcriber.start(audio: SilentAudioInput())
        var command: Command?
        for await c in stream { command = c; break }
        transcriber.stop(); commands.detach()
        XCTAssertEqual(command, .whoIsHere)
        for _ in 0..<40 where perception.currentTracks().count != 1 { try await Task.sleep(nanoseconds: 50_000_000) }   // let the last script event land under load
        let rollCall = RollCall.utterance(tracks: perception.currentTracks())
        XCTAssertTrue(rollCall.text.hasPrefix("Marcus, 12 o'clock, close."), rollCall.text)
        await speaker.speak(rollCall)
        XCTAssertEqual(speaker.spoken.last?.utterance.text, rollCall.text)

        // Mute: ordinary cues are gated, confirmations (priority 0) still pass.
        gate.muted = true
        let marcusID = perception.currentTracks().first?.identity.personID ?? UUID()
        let leftCue = Utterance(text: Phrasebook.left(name: "Marcus"), priority: 2, category: "left", personID: marcusID, dedupeKey: "left:\(marcusID)", audience: .user, earcon: true)
        XCTAssertFalse(gate.admit(leftCue))
        XCTAssertTrue(gate.admit(Utterance(text: Phrasebook.saved(name: "Marcus"), priority: 0, category: "consent", personID: marcusID, dedupeKey: nil, audience: .user, earcon: true)))
    }
}
