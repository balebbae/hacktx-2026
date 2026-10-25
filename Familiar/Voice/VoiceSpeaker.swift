import Foundation
import QuartzCore
import os

/// The production `Speaker`: a priority queue in front of one synthesizer and one playback.
/// - priority 0 interrupts whatever is playing and clears the queue;
/// - priorities 1–3 are FIFO with depth `maxQueued` (the lowest-priority queued item is dropped when full);
/// - an utterance with the same `dedupeKey` replaces the queued one;
/// - utterances of priority ≥ 1 start at least `minimumSpacing` after the previous utterance ended;
/// - `prewarm` synthesizes into the cache with concurrency 2.
final class VoiceSpeaker: Speaker, @unchecked Sendable {
    typealias Clock = () -> TimeInterval
    typealias Sleep = (TimeInterval) async -> Void

    struct Spoken: Equatable { let utterance: Utterance; let window: ClosedRange<TimeInterval>?; let source: String }

    var minimumSpacing: TimeInterval = 4
    var maxQueued = 2
    var leadingSilence: TimeInterval = 0.15
    /// Fires for every utterance that reached playback (the judge view's utterance log).
    var onSpoken: ((Spoken) -> Void)?
    var onDropped: ((Utterance, String) -> Void)?
    /// The wearer's volume preference as a 0…1 gain, read per utterance (`VoiceFactory` wires `SpeechPreferences`).
    /// nil, the default for speakers built directly (tests), means unity.
    var volumeProvider: (() -> Float)?

    private struct Job {
        let id = UUID()
        let utterance: Utterance
        let continuation: CheckedContinuation<ClosedRange<TimeInterval>?, Never>
    }
    private struct State {
        var queue: [Job] = []
        var current: Job?
        var workerRunning = false
        var lastEnd: TimeInterval?
        var speaking = false
    }

    let synthesizer: SpeechSynthesizer
    let playback: PCMPlayback
    private let clock: Clock
    private let sleep: Sleep
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let spokenLog = OSAllocatedUnfairLock(initialState: [Spoken]())

    init(synthesizer: SpeechSynthesizer, playback: PCMPlayback, clock: @escaping Clock = { CACurrentMediaTime() }, sleep: Sleep? = nil) {
        self.synthesizer = synthesizer
        self.playback = playback
        self.clock = clock
        self.sleep = sleep ?? { seconds in try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    }

    var isSpeaking: Bool { state.withLock { $0.speaking } }
    var queuedCount: Int { state.withLock { $0.queue.count } }
    var spoken: [Spoken] { spokenLog.withLock { $0 } }

    @discardableResult
    func speak(_ u: Utterance) async -> ClosedRange<TimeInterval>? {
        await withCheckedContinuation { (cont: CheckedContinuation<ClosedRange<TimeInterval>?, Never>) in
            let job = Job(utterance: u, continuation: cont)
            var dropped: [(Job, String)] = []
            var interrupt = false
            let startWorker: Bool = state.withLock { s in
                if u.priority == 0 {
                    dropped = s.queue.map { ($0, "cleared by priority 0") }
                    s.queue = [job]
                    interrupt = s.current != nil
                } else {
                    if let key = u.dedupeKey, let i = s.queue.firstIndex(where: { $0.utterance.dedupeKey == key }) {
                        dropped.append((s.queue.remove(at: i), "replaced by same dedupeKey"))
                    }
                    s.queue.append(job)
                    s.queue.sort { $0.utterance.priority < $1.utterance.priority }   // stable: FIFO within a priority
                    while s.queue.count > maxQueued {
                        if let i = s.queue.indices.last(where: { s.queue[$0].utterance.priority >= u.priority }) ?? s.queue.indices.last {
                            dropped.append((s.queue.remove(at: i), "queue full"))
                        }
                    }
                }
                if s.workerRunning { return false }
                s.workerRunning = true
                return true
            }
            for (j, why) in dropped { onDropped?(j.utterance, why); j.continuation.resume(returning: nil) }
            if interrupt { playback.stop() }
            if startWorker { Task.detached(priority: .userInitiated) { [weak self] in await self?.run() } }
        }
    }

    private func run() async {
        while true {
            let next: Job? = state.withLock { s in
                guard !s.queue.isEmpty else { s.workerRunning = false; return nil }
                let j = s.queue.removeFirst()
                s.current = j
                return j
            }
            guard let job = next else { return }
            let window = await perform(job)
            state.withLock { s in
                if s.current?.id == job.id { s.current = nil }
                s.speaking = false
                if let window { s.lastEnd = window.upperBound }
            }
            job.continuation.resume(returning: window)
        }
    }

    private func perform(_ job: Job) async -> ClosedRange<TimeInterval>? {
        let u = job.utterance
        if u.priority >= 1, let lastEnd = state.withLock({ $0.lastEnd }) {
            let wait = lastEnd + minimumSpacing - clock()
            if wait > 0 { await sleep(wait) }
            if !isCurrent(job) { return nil }    // interrupted while waiting
        }
        let audio: SynthesizedAudio
        do { audio = try await synthesizer.synthesize(u.text) } catch {
            onDropped?(u, "synthesis failed: \(error)")
            return nil
        }
        guard isCurrent(job) else { return nil }
        var samples = [Float](repeating: 0, count: Int(leadingSilence * audio.sampleRate))
        if u.earcon { samples += Earcon.prefix(for: audio.sampleRate) }
        samples += audio.samples
        var gain = SpeakerVolumeHint.gain(for: u)   // S7: whispered cues
        if let volumeProvider { gain *= min(1, max(0, volumeProvider())) }   // the wearer's volume preference
        if gain != 1 { samples = samples.map { $0 * gain } }
        state.withLock { $0.speaking = true }
        let window = await playback.play(SynthesizedAudio(samples: samples, sampleRate: audio.sampleRate, source: audio.source), audience: u.audience)
        let spoken = Spoken(utterance: u, window: window, source: audio.source)
        spokenLog.withLock { $0.append(spoken); if $0.count > 200 { $0.removeFirst() } }
        onSpoken?(spoken)
        return window
    }

    private func isCurrent(_ job: Job) -> Bool { state.withLock { $0.current?.id == job.id } }

    func stopAll() {
        let dropped: [Job] = state.withLock { s in
            let q = s.queue; s.queue.removeAll(); s.current = nil; s.speaking = false; return q
        }
        playback.stop()
        for j in dropped { onDropped?(j.utterance, "stopAll"); j.continuation.resume(returning: nil) }
    }

    func prewarm(_ phrases: [String]) async {
        let synth = self.synthesizer
        await withTaskGroup(of: Void.self) { group in
            var iterator = phrases.makeIterator()
            var running = 0
            while let phrase = iterator.next() {
                if running >= 2 { await group.next(); running -= 1 }
                running += 1
                group.addTask { await VoiceSpeaker.warm(phrase, with: synth) }
            }
            await group.waitForAll()
        }
    }

    private static func warm(_ phrase: String, with synth: SpeechSynthesizer) async {
        if let fallback = synth as? FallbackSynthesizer, let eleven = fallback.primary as? ElevenLabsTTS {
            try? await eleven.warm(phrase)
        } else if let eleven = synth as? ElevenLabsTTS {
            try? await eleven.warm(phrase)
        } else {
            _ = try? await synth.synthesize(phrase)
        }
    }
}
