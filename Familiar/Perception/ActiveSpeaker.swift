import Foundation
import os

// S7 (stretch): who is talking to me. Perception-only types; nothing here changes a Core contract.

struct ActiveSpeakerConfig: Equatable {
    /// Seconds of mouth-openness history the variance is computed over.
    var window: TimeInterval = 1.0
    /// Variance of (inner-lip gap ÷ face height) above which a mouth counts as moving. A mouth swinging 0 → 0.12 of the
    /// face height while talking has variance ≈ 0.0018; landmark jitter on a closed mouth is ≈ 1e-4. The plan's 0.004
    /// needs a 0 → 0.18 swing (shouting), so the default sits between; re-tune on a real iPhone (see PR notes).
    var varianceThreshold: Double = 0.0015
    /// How long the winning track must stay above threshold before it is called the speaker.
    var sustain: TimeInterval = 0.6
    /// Fewer samples than this in the window and the variance is not trusted (15 fps → ~15 samples per second).
    var minSamples = 6
    /// Keep treating `.other` speech as active this long after the VAD last said so (word gaps, VAD hangover).
    var voiceHangover: TimeInterval = 0.5
    /// A person already announced is eligible again once their track has been gone this long.
    var resetAfterLost: TimeInterval = 300
    /// After naming one speaker, wait this long before another candidate can start building evidence
    /// (two mouths moving at once is "unsure", and unsure means silence).
    var announceCooldown: TimeInterval = 2.0
    static let `default` = ActiveSpeakerConfig()
}

/// Decides which **known**, facing track is speaking to the wearer and gates `speakingStarted` to once per track-session.
///
/// Inputs: the `VoiceActivity` verdict (`isSpeech` with `guess == .other`; `.user` speech cancels) and each known track's
/// mouth-openness series kept by `FaceTracker`. While other-speech is active, the candidate with the highest variance
/// over the last `window` seconds, above `varianceThreshold` and sustained for `sustain` seconds, is the speaker.
/// Unknown tracks are never candidates: strangers are not described. Thread-safe; `evaluate` is called from the
/// pipeline's frame loop, `noteVoice` from the VAD stream.
final class ActiveSpeaker: @unchecked Sendable {
    struct Candidate {
        let trackID: Int
        let personID: UUID
        let isFacingUser: Bool
        let mouth: [(t: TimeInterval, openness: Double)]
    }

    private struct State {
        var otherSpeechActive = false
        var lastOtherSpeech: TimeInterval = -.infinity
        var sustainedSince: [Int: TimeInterval] = [:]
        var announced: [UUID: (trackID: Int, lastSeen: TimeInterval)] = [:]
        var lastAnnouncedAt: TimeInterval = -.infinity
    }

    let config: ActiveSpeakerConfig
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var voiceTask: Task<Void, Never>?

    init(config: ActiveSpeakerConfig = .default) { self.config = config }

    deinit { voiceTask?.cancel() }

    // MARK: - Voice

    /// Feed one VAD sample (host-clock seconds, like the frames).
    func noteVoice(isSpeech: Bool, guess: SpeakerGuess, t: TimeInterval) {
        state.withLock { s in
            if isSpeech, guess == .other {
                s.otherSpeechActive = true
                s.lastOtherSpeech = t
            } else {
                if s.otherSpeechActive { s.lastOtherSpeech = max(s.lastOtherSpeech, t) }
                s.otherSpeechActive = false
                // The wearer talking is not "someone talking to me": drop any half-built evidence.
                if guess == .user { s.lastOtherSpeech = -.infinity; s.sustainedSince.removeAll() }
            }
        }
    }

    /// Subscribe to a VAD for the lifetime of this object (one subscriber; `stop()` cancels it).
    func attach(_ voice: VoiceActivity) {
        guard voiceTask == nil else { return }
        let stream = voice.subscribe()
        voiceTask = Task.detached { [weak self] in
            for await sample in stream {
                guard let self, !Task.isCancelled else { break }
                self.noteVoice(isSpeech: sample.isSpeech, guess: sample.guess, t: sample.t)
            }
        }
    }

    func stop() { voiceTask?.cancel(); voiceTask = nil }

    func reset() { state.withLock { $0 = State() } }

    /// True while the VAD attributes speech to the other person (with `voiceHangover` to bridge word gaps).
    func otherIsSpeaking(at now: TimeInterval) -> Bool {
        state.withLock { s in s.otherSpeechActive || now - s.lastOtherSpeech <= config.voiceHangover }
    }

    // MARK: - Evaluation

    /// Call once per processed frame with the known, confirmed tracks visible in it. Returns the track ID to emit
    /// `speakingStarted` for (at most one per call), or nil.
    func evaluate(_ candidates: [Candidate], now: TimeInterval) -> Int? {
        state.withLock { s in
            // Track-session bookkeeping: an announced person stays silent until gone for `resetAfterLost`.
            s.announced = s.announced.filter { now - $0.value.lastSeen <= config.resetAfterLost }
            for c in candidates where s.announced[c.personID] != nil { s.announced[c.personID]?.lastSeen = now }
            let present = Set(candidates.map(\.trackID))
            s.sustainedSince = s.sustainedSince.filter { present.contains($0.key) }

            guard now - s.lastAnnouncedAt >= config.announceCooldown,
                  s.otherSpeechActive || now - s.lastOtherSpeech <= config.voiceHangover else {
                s.sustainedSince.removeAll()
                return nil
            }

            var best: (trackID: Int, personID: UUID, variance: Double)?
            for c in candidates where c.isFacingUser && s.announced[c.personID] == nil {
                guard let v = Self.variance(c.mouth, since: now - config.window, minSamples: config.minSamples), v >= config.varianceThreshold else { continue }
                if best == nil || v > best!.variance { best = (c.trackID, c.personID, v) }
            }
            guard let best else { s.sustainedSince.removeAll(); return nil }
            s.sustainedSince = s.sustainedSince.filter { $0.key == best.trackID }
            let since = s.sustainedSince[best.trackID] ?? now
            s.sustainedSince[best.trackID] = since
            guard now - since >= config.sustain else { return nil }
            s.announced[best.personID] = (best.trackID, now)
            s.lastAnnouncedAt = now
            s.sustainedSince.removeAll()
            return best.trackID
        }
    }

    /// Population variance of the samples at or after `since`, or nil with fewer than `minSamples`.
    static func variance(_ series: [(t: TimeInterval, openness: Double)], since: TimeInterval, minSamples: Int) -> Double? {
        var n = 0.0, sum = 0.0, sumSq = 0.0
        for s in series where s.t >= since {
            n += 1; sum += s.openness; sumSq += s.openness * s.openness
        }
        guard n >= Double(max(1, minSamples)) else { return nil }
        let mean = sum / n
        return max(0, sumSq / n - mean * mean)
    }

    /// People currently suppressed (announced in this track-session), for the judge view and tests.
    var announcedPeople: Set<UUID> { state.withLock { Set($0.announced.keys) } }
}

extension ActiveSpeaker.Candidate {
    /// A known track as the pipeline sees it; nil for unknown tracks so strangers can never become candidates.
    init?(track: FaceTrack) {
        guard let pid = track.identity.personID else { return nil }
        self.init(trackID: track.id, personID: pid, isFacingUser: track.isFacingUser, mouth: track.mouthSeries)
    }
}
