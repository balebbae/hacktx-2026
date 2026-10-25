import Foundation
import AVFoundation
import QuartzCore
import os

/// `Speaker` for the Simulator and tests: logs every utterance with a timestamp, optionally voices it with
/// `AVSpeechSynthesizer`, and returns a synthetic playback window (0.25 s per word). Priority 0 interrupts.
final class LogSpeaker: NSObject, Speaker, @unchecked Sendable {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let at: TimeInterval
        let utterance: Utterance
        var window: ClosedRange<TimeInterval>?
    }

    typealias Clock = () -> TimeInterval

    /// When true, utterances are also spoken through AVSpeechSynthesizer (fine in the Simulator).
    var speakAloud: Bool
    /// When false, `speak` returns immediately after logging (tests). When true it waits for the synthetic window.
    var simulateDuration: Bool
    var secondsPerWord: TimeInterval = 0.25

    private let clock: Clock
    private let synthesizer = AVSpeechSynthesizer()
    private let log = OSAllocatedUnfairLock(initialState: [Entry]())
    private let bus = EventBus<Entry>()
    private let speakingLock = OSAllocatedUnfairLock(initialState: (speaking: false, generation: 0))
    private let prewarmed = OSAllocatedUnfairLock(initialState: Set<String>())

    init(speakAloud: Bool = false, simulateDuration: Bool = true, clock: @escaping Clock = { CACurrentMediaTime() }) {
        self.speakAloud = speakAloud
        self.simulateDuration = simulateDuration
        self.clock = clock
        super.init()
    }

    var entries: [Entry] { log.withLock { $0 } }
    var texts: [String] { entries.map(\.utterance.text) }
    func subscribe() -> AsyncStream<Entry> { bus.subscribe() }
    var prewarmedPhrases: Set<String> { prewarmed.withLock { $0 } }

    var isSpeaking: Bool { speakingLock.withLock { $0.speaking } }

    @discardableResult
    func speak(_ u: Utterance) async -> ClosedRange<TimeInterval>? {
        let start = clock()
        let words = max(1, u.text.split(separator: " ").count)
        let duration = Double(words) * secondsPerWord
        let window = start...(start + duration)
        var entry = Entry(at: start, utterance: u, window: window)
        let generation: Int = speakingLock.withLock { s in
            if u.priority == 0 { s.generation += 1; synthesizer.stopSpeaking(at: .immediate) }
            s.speaking = true
            return s.generation
        }
        log.withLock { $0.append(entry) }
        bus.publish(entry)
        NSLog("[LogSpeaker] %.2f p%d %@ (%@) %@", start, u.priority, u.category, u.audience == .user ? "user" : "other", u.text)
        if speakAloud {
            let su = AVSpeechUtterance(string: u.text)
            su.voice = AVSpeechSynthesisVoice(language: "en-US")
            let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(SpeechPreferences.rateMultiplier())
            su.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))
            su.volume = Float(SpeechPreferences.volume())
            synthesizer.speak(su)
        }
        if simulateDuration {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
        let interrupted = speakingLock.withLock { s -> Bool in
            let wasInterrupted = s.generation != generation
            if !wasInterrupted { s.speaking = false }
            return wasInterrupted
        }
        if interrupted { entry.window = start...clock(); return entry.window }
        return window
    }

    func stopAll() {
        speakingLock.withLock { s in s.generation += 1; s.speaking = false }
        synthesizer.stopSpeaking(at: .immediate)
    }

    func prewarm(_ phrases: [String]) async {
        prewarmed.withLock { $0.formUnion(phrases) }
    }

    func clear() { log.withLock { $0.removeAll() } }
}
