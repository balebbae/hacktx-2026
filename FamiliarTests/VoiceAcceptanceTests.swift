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
        var log: [String] = []
        speaker.onSpoken = { log.append("\(Int($0.window?.lowerBound ?? 0)) \($0.utterance.text)") }

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

        XCTAssertEqual(speaker.spoken.map(\.utterance.text), [
            "Marcus, far right, far.",
            "Marcus, coming from your right.",
            "Marcus, next to you.",
            "Marcus.",
            "Marcus left.",
            "Marcus, left, medium.",
            "Marcus, next to you.",
        ])
        print("[VoiceAcceptanceTests] spoken:\n" + log.joined(separator: "\n"))
        XCTAssertFalse(speaker.spoken.contains { $0.utterance.text.localizedCaseInsensitiveContains("familiar") })
        XCTAssertFalse(speaker.spoken.contains { $0.utterance.text.localizedCaseInsensitiveContains("someone") }, "strangers are silent in normal mode")

        // Wake word → command → roll call over the final scene (Marcus close ahead, no strangers).
        let transcriber = FakeTranscriber(text: "other: Hi, I'm Marcus.\nuser: Familiar, who's here?", interval: 0.01)
        let commands = SpeechFactory.makeCommandSource(transcriber: transcriber)
        let stream = commands.subscribe()
        try await transcriber.start(audio: SilentAudioInput())
        var command: Command?
        for await c in stream { command = c; break }
        transcriber.stop(); commands.detach()
        XCTAssertEqual(command, .whoIsHere)
        let rollCall = RollCall.utterance(tracks: perception.currentTracks())
        XCTAssertEqual(rollCall.text, "Marcus, ahead, close. No one else.")
        await speaker.speak(rollCall)
        XCTAssertEqual(speaker.spoken.last?.utterance.text, rollCall.text)

        // Mute: ordinary cues are gated, confirmations (priority 0) still pass.
        gate.muted = true
        let marcusID = perception.currentTracks().first?.identity.personID ?? UUID()
        let cue = policy.utterances(for: .knownLeft(personID: marcusID, name: "Marcus", last: Bearing(degrees: 0, band: .ahead)), mode: .normal, now: clock.now)
        XCTAssertEqual(cue.map(\.text), ["Marcus left."])
        XCTAssertFalse(gate.admit(cue[0]))
        XCTAssertTrue(gate.admit(Utterance(text: Phrasebook.saved(name: "Marcus"), priority: 0, category: "consent", personID: marcusID, dedupeKey: nil, audience: .user, earcon: true)))
    }
}
