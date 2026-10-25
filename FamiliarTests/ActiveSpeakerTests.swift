import XCTest
@testable import Familiar

/// S7: synthetic mouth-openness series + VAD verdicts → `ActiveSpeaker` decisions.
final class ActiveSpeakerTests: XCTestCase {
    let marcus = UUID()
    let priya = UUID()
    let fps: TimeInterval = 15

    /// Mouth-openness samples from `from` up to `to`: a talking mouth oscillates between 0.0 and 0.12 (≈ 5 Hz),
    /// a quiet one sits at 0.02 with sensor jitter.
    func series(from: TimeInterval, to: TimeInterval, talking: Bool, amplitude: Double = 0.06) -> [(t: TimeInterval, openness: Double)] {
        var out: [(t: TimeInterval, openness: Double)] = []
        var t = from
        var i = 0
        while t <= to + 1e-9 {
            let o = talking ? amplitude + amplitude * sin(Double(i) * 2) : 0.02 + 0.002 * sin(Double(i))
            out.append((t, o))
            t += 1 / fps; i += 1
        }
        return out.filter { $0.t >= to - 1.5 }   // FaceTracker keeps 1.5 s
    }

    func candidate(_ id: Int, _ pid: UUID, talking: Bool, at now: TimeInterval, facing: Bool = true) -> ActiveSpeaker.Candidate {
        ActiveSpeaker.Candidate(trackID: id, personID: pid, isFacingUser: facing, mouth: series(from: 0, to: now, talking: talking))
    }

    /// Runs frames at 15 fps from `from` to `to` and returns the (time, trackID) of every emission.
    func run(_ speaker: ActiveSpeaker, from: TimeInterval, to: TimeInterval, tracks: (TimeInterval) -> [ActiveSpeaker.Candidate]) -> [(t: TimeInterval, track: Int)] {
        var hits: [(TimeInterval, Int)] = []
        var t = from
        while t <= to + 1e-9 {
            if let id = speaker.evaluate(tracks(t), now: t) { hits.append((t, id)) }
            t += 1 / fps
        }
        return hits
    }

    func testOnlyTheOscillatingMouthTriggers() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        let hits = run(s, from: 2.0, to: 5.0) { now in
            [candidate(1, marcus, talking: true, at: now), candidate(2, priya, talking: false, at: now)]
        }
        XCTAssertEqual(hits.map(\.track), [1], "only Marcus's track speaks, exactly once")
        XCTAssertGreaterThanOrEqual(hits.first?.t ?? 0, 2.6, "sustained for at least 0.6 s before firing")
        XCTAssertLessThan(hits.first?.t ?? 99, 3.5, "and fires within about a second of speech starting")
        XCTAssertEqual(s.announcedPeople, [marcus])
    }

    func testNoTriggerWhenTheWearerIsTalking() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .user, t: 2.0)
        let hits = run(s, from: 2.0, to: 6.0) { now in [candidate(1, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.count, 0, "VAD says .user: a moving mouth is not evidence")

        // Silence either.
        s.noteVoice(isSpeech: false, guess: .none, t: 6.0)
        XCTAssertEqual(run(s, from: 6.6, to: 9.0) { now in [candidate(1, marcus, talking: true, at: now)] }.count, 0)
        XCTAssertEqual(s.announcedPeople, [])
    }

    func testUserSpeechCancelsHalfBuiltEvidence() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        _ = run(s, from: 2.0, to: 2.4) { now in [candidate(1, marcus, talking: true, at: now)] }
        s.noteVoice(isSpeech: true, guess: .user, t: 2.45)
        XCTAssertEqual(run(s, from: 2.46, to: 3.0) { now in [candidate(1, marcus, talking: true, at: now)] }.count, 0)
        s.noteVoice(isSpeech: true, guess: .other, t: 3.0)
        let hits = run(s, from: 3.0, to: 4.5) { now in [candidate(1, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.map(\.track), [1])
        XCTAssertGreaterThanOrEqual(hits.first?.t ?? 0, 3.6, "the 0.6 s sustain restarts after the wearer spoke")
    }

    func testExactlyOneEventPerTrackSession() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        var hits = run(s, from: 2.0, to: 12.0) { now in [candidate(1, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.count, 1, "ten seconds of talking, one event")

        // Pauses and new sentences within the same track-session stay silent.
        s.noteVoice(isSpeech: false, guess: .none, t: 12.0)
        s.noteVoice(isSpeech: true, guess: .other, t: 15.0)
        hits = run(s, from: 15.0, to: 20.0) { now in [candidate(1, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.count, 0)

        // Marcus steps out and comes back as a new track 30 s later: same session, still silent.
        hits = run(s, from: 50.0, to: 55.0) { now in [candidate(9, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.count, 0, "re-detected within 5 minutes: not announced again")
        XCTAssertEqual(s.announcedPeople, [marcus])

        // Gone for more than five minutes: a fresh track-session.
        hits = run(s, from: 400.0, to: 405.0) { now in [candidate(12, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.map(\.track), [12])
    }

    func testTwoTalkersPickTheHigherVarianceAndTheOtherLater() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        let loud = { (now: TimeInterval) in ActiveSpeaker.Candidate(trackID: 1, personID: self.marcus, isFacingUser: true, mouth: self.series(from: 0, to: now, talking: true, amplitude: 0.09)) }
        let mild = { (now: TimeInterval) in self.candidate(2, self.priya, talking: true, at: now) }
        var hits = run(s, from: 2.0, to: 4.5) { now in [loud(now), mild(now)] }
        XCTAssertEqual(hits.map(\.track), [1], "the biggest mouth movement wins; one speaker per moment, then a 2 s cooldown")
        hits = run(s, from: 4.5, to: 7.0) { now in [loud(now), mild(now)] }
        XCTAssertEqual(hits.map(\.track), [2], "once Marcus is announced and the cooldown passed, Priya's sustained movement is next")
    }

    func testNotFacingDoesNotCount() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        let hits = run(s, from: 2.0, to: 5.0) { now in [candidate(1, marcus, talking: true, at: now, facing: false)] }
        XCTAssertEqual(hits.count, 0, "talking to someone else, not to the wearer")
    }

    func testVoiceHangoverBridgesWordGaps() {
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 2.0)
        s.noteVoice(isSpeech: false, guess: .none, t: 2.2)   // 300 ms gap between words
        XCTAssertTrue(s.otherIsSpeaking(at: 2.5))
        XCTAssertFalse(s.otherIsSpeaking(at: 2.8))
        s.noteVoice(isSpeech: true, guess: .other, t: 2.5)
        let hits = run(s, from: 2.0, to: 4.0) { now in [candidate(1, marcus, talking: true, at: now)] }
        XCTAssertEqual(hits.count, 1)
    }

    func testUnknownTracksAreNeverCandidates() {
        let det = FaceDetection(box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), confidence: 0.9, mouthOpenness: 0.05)
        let stranger = FaceTrack(id: 1, detection: det, at: 0, matcher: .default)
        XCTAssertNil(ActiveSpeaker.Candidate(track: stranger))
        let known = FaceTrack(id: 2, detection: det, at: 0, matcher: .default)
        known.votes.assign(personID: marcus, name: "Marcus")
        XCTAssertEqual(ActiveSpeaker.Candidate(track: known)?.personID, marcus)
    }

    /// End to end through `FaceTracker`: detections with mouth openness build the series the pipeline hands over.
    func testTrackerSeriesFeedsTheDetector() {
        let tracker = FaceTracker()
        let s = ActiveSpeaker()
        s.noteVoice(isSpeech: true, guess: .other, t: 0)
        var hits: [Int] = []
        var t: TimeInterval = 0
        var i = 0
        while t <= 3.0 {
            let talking = FaceDetection(box: CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.2), confidence: 0.9, yawDegrees: 5, mouthOpenness: 0.06 + 0.06 * sin(Double(i) * 2))
            let quiet = FaceDetection(box: CGRect(x: 0.6, y: 0.3, width: 0.2, height: 0.2), confidence: 0.9, yawDegrees: -5, mouthOpenness: 0.02)
            tracker.update([talking, quiet], at: t)
            for tr in tracker.tracks where tr.isConfirmed && !tr.isKnown {
                tr.votes.assign(personID: tr.id == 1 ? marcus : priya, name: tr.id == 1 ? "Marcus" : "Priya")
            }
            let cands = tracker.visible(at: t).filter(\.isConfirmed).compactMap(ActiveSpeaker.Candidate.init(track:))
            if let id = s.evaluate(cands, now: t) { hits.append(id) }
            t += 1 / fps; i += 1
        }
        XCTAssertEqual(hits, [1])
    }

    func testVarianceHelper() {
        let flat = (0..<10).map { (t: Double($0) * 0.1, openness: 0.02) }
        XCTAssertEqual(ActiveSpeaker.variance(flat, since: 0, minSamples: 6) ?? -1, 0, accuracy: 1e-12)
        XCTAssertNil(ActiveSpeaker.variance(flat, since: 0.6, minSamples: 6), "too few samples in the window")
        let osc = (0..<10).map { (t: Double($0) * 0.1, openness: $0 % 2 == 0 ? 0.0 : 0.12) }
        XCTAssertEqual(ActiveSpeaker.variance(osc, since: 0, minSamples: 6) ?? -1, 0.0036, accuracy: 1e-9)
    }

    // MARK: - Cue + volume

    func testCuePolicySpeakingCueIsPriorityOneWithoutEarcon() {
        let policy = FamiliarCuePolicy()
        let t = TestTracks.known("Marcus", id: marcus, track: 4)
        let u = policy.utterances(for: .speakingStarted(t), mode: .normal, now: 1)
        XCTAssertEqual(u.map(\.text), ["Marcus."])
        XCTAssertEqual(u.first?.priority, 1)
        XCTAssertEqual(u.first?.earcon, false)
        XCTAssertEqual(u.first.map(SpeakerVolumeHint.gainDB(for:)), -6)
        XCTAssertEqual(policy.utterances(for: .speakingStarted(t), mode: .chatty, now: 2), [], "once per track")
        let other = policy.utterances(for: .knownArrived(t), mode: .normal, now: 3)
        XCTAssertEqual(other.first.map(SpeakerVolumeHint.gainDB(for:)), 0)
    }

    func testSpeakerPlaysSpeakingCueSixDecibelsQuieter() async {
        let clock = ManualClock(10)
        let synth = FakeSynth()
        let playback = FakePlayback(clock: { clock.now })
        let speaker = VoiceSpeaker(synthesizer: synth, playback: playback, clock: { clock.now }, sleep: { _ in })
        let whisper = Utterance(text: "Marcus.", priority: 1, category: "speaking", personID: marcus, dedupeKey: "speaking:\(marcus.uuidString)", audience: .user, earcon: false)
        await speaker.speak(whisper)
        await speaker.speak(.test("Marcus, next to you."))
        let played = playback.played
        XCTAssertEqual(played.count, 2)
        XCTAssertEqual(played[0].samples.max() ?? 0, 0.1 * powf(10, -6 / 20), accuracy: 1e-4)
        XCTAssertEqual(played[1].samples.max() ?? 0, 0.1, accuracy: 1e-6)
    }
}
