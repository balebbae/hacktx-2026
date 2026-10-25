import Foundation
import QuartzCore
import os

/// The production `Speaker`: a priority queue in front of one synthesizer and one playback.
/// - priority 0 interrupts whatever is playing and clears the queue;
/// - priorities 1–3 are FIFO with depth `maxQueued` (the lowest-priority queued item is dropped when full);
/// - an utterance with the same `dedupeKey` replaces the queued one;
/// - utterances of priority ≥ 1 start at least `minimumSpacing` after the previous utterance ended;
/// - uncached text streams from the synthesizer into playback when both sides can (`streaming`), so the first word
///   plays before the last is synthesized; a stream that never starts falls back to the plain path;
/// - the line just spoken becomes the synthesizer's `previous_text`, so consecutive lines sound like one voice;
/// - `prewarm` synthesizes into the cache with concurrency 2.
final class VoiceSpeaker: Speaker, @unchecked Sendable {
    typealias Clock = () -> TimeInterval
    typealias Sleep = (TimeInterval) async -> Void

    struct Spoken: Equatable { let utterance: Utterance; let window: ClosedRange<TimeInterval>?; let source: String }

    var minimumSpacing: TimeInterval = 1.5
    var maxQueued = 2
    /// Bluetooth output swallows the first ~150 ms after silence; wired or built-in output needs no lead-in.
    var leadingSilence: TimeInterval = 0.15
    /// Whether the current output route is Bluetooth; nil (tests) keeps the lead-in.
    var isBluetoothOutput: (() -> Bool)?
    var streaming = true
    /// Someone is speaking right now (the recognizer has in-progress text). Routine lines (priority ≥ 1) wait for
    /// the pause, at most `maxHoldForSpeech`, so a cue does not start on top of the wearer's "Poyo, …" and mute
    /// the mic under it. nil (tests) never holds.
    var speechInProgress: (() -> Bool)?
    var maxHoldForSpeech: TimeInterval = 2.5
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
        if u.text.isEmpty {
            // Earcon-only acknowledgement ("heard you"): no synthesis, and nil so it never delays the next cue.
            guard u.earcon else { return nil }
            state.withLock { $0.speaking = true }
            _ = await playback.play(SynthesizedAudio(samples: Earcon.prefix(for: Earcon.sampleRate), sampleRate: Earcon.sampleRate, source: "earcon"), audience: u.audience)
            return nil
        }
        if u.priority >= 1, let lastEnd = state.withLock({ $0.lastEnd }) {
            let wait = lastEnd + minimumSpacing - clock()
            if wait > 0 { await sleep(wait) }
            if !isCurrent(job) { return nil }    // interrupted while waiting
        }
        if u.priority >= 1, let busy = speechInProgress {
            // Bounded by count as well as time, so a stopped test clock cannot spin here.
            for _ in 0..<Int(maxHoldForSpeech / 0.1) where busy() {
                await sleep(0.1)
                if !isCurrent(job) { return nil }
            }
        }
        var gain = SpeakerVolumeHint.gain(for: u)   // S7: whispered cues
        if let volumeProvider { gain *= min(1, max(0, volumeProvider())) }   // the wearer's volume preference
        func prefix(for sampleRate: Double) -> [Float] {
            var p = [Float](repeating: 0, count: Int(((isBluetoothOutput?() ?? true) ? leadingSilence : 0) * sampleRate))
            if u.earcon { p += Earcon.prefix(for: sampleRate) }
            return p
        }
        var streamError: Error?
        if streaming, let synth = synthesizer as? StreamingSpeechSynthesizer, let player = playback as? StreamingPCMPlayback, let stream = synth.stream(u.text) {
            // The first chunk decides: in hand → play as it arrives; a failure → the plain path (and its fallback voice).
            var iterator = stream.makeAsyncIterator()
            do {
                guard let first = try await iterator.next() else { throw ElevenLabsTTS.Failure.emptyAudio }
                guard isCurrent(job) else { return nil }
                let rest = AsyncThrowingStream<[Float], Error> { cont in
                    cont.yield(first)
                    let t = Task { [iterator] in
                        var it = iterator       // the copy shares the stream's storage; one consumer still
                        do { while let chunk = try await it.next() { cont.yield(chunk) }; cont.finish() } catch { cont.finish(throwing: error) }
                    }
                    cont.onTermination = { _ in t.cancel() }
                }
                state.withLock { $0.speaking = true }
                let window = await player.playStream(rest, sampleRate: synth.streamSampleRate, prefix: prefix(for: synth.streamSampleRate), gain: gain, audience: u.audience)
                return finish(job, window: window, source: "elevenlabs-stream")
            } catch {
                streamError = error
            }
        }
        let audio: SynthesizedAudio
        do {
            if let streamError, let fb = synthesizer as? FallbackSynthesizer { audio = try await fb.synthesizeAfterPrimaryFailed(u.text, error: streamError) }
            else { audio = try await synthesizer.synthesize(u.text) }
        } catch {
            onDropped?(u, "synthesis failed: \(error)")
            return nil
        }
        guard isCurrent(job) else { return nil }
        var samples = prefix(for: audio.sampleRate) + audio.samples
        if gain != 1 { samples = samples.map { $0 * gain } }
        state.withLock { $0.speaking = true }
        let window = await playback.play(SynthesizedAudio(samples: samples, sampleRate: audio.sampleRate, source: audio.source), audience: u.audience)
        return finish(job, window: window, source: audio.source)
    }

    private func finish(_ job: Job, window: ClosedRange<TimeInterval>?, source: String) -> ClosedRange<TimeInterval>? {
        let u = job.utterance
        let spoken = Spoken(utterance: u, window: window, source: source)
        spokenLog.withLock { $0.append(spoken); if $0.count > 200 { $0.removeFirst() } }
        // One voice: the next line is synthesized as a continuation of this one.
        if window != nil, u.audience == .user { Self.elevenLabs(in: synthesizer)?.previousText = u.text }
        onSpoken?(spoken)
        return window
    }

    private static func elevenLabs(in synth: SpeechSynthesizer) -> ElevenLabsTTS? {
        (synth as? ElevenLabsTTS) ?? ((synth as? FallbackSynthesizer)?.primary as? ElevenLabsTTS)
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
        if let eleven = elevenLabs(in: synth) { try? await eleven.warm(phrase) } else { _ = try? await synth.synthesize(phrase) }
    }
}
