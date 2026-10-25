import Foundation
import QuartzCore
import os

/// Watches recognizer text for "Poyo" (plus common mishearings), then hands the request that follows to
/// `CommandParser` / the assistant as soon as it is complete:
/// - a final segment with text after the wake word emits at once, parsed or not;
/// - in-progress (volatile) text emits once it has not changed for `settle` seconds, or `endpointSettle` seconds
///   after the recognizer's voice-activity detector said speech stopped (`endpoint(at:)`); the final that later
///   arrives for the same utterance is swallowed;
/// - a bare "Poyo." waits up to `collectWindow` seconds for the next final.
final class WakeWord: @unchecked Sendable {
    var collectWindow: TimeInterval = 3
    var settle: TimeInterval = 0.5
    /// After speech stopped, how long the volatile text must hold still (the recognizer finishes the words it
    /// already heard a beat later).
    var endpointSettle: TimeInterval = 0.25
    var onHit: ((WakeWordHit) -> Void)?

    static let target = "poyo"
    static let aliases: Set<String> = ["poyo", "poyos", "poyo's", "pollo", "poio", "poyoh", "boyo", "pojo", "poyo,"]
    static let twoWordAliases: Set<String> = ["po yo", "poe yo", "pull yo", "bo yo", "poh yo"]
    /// Biases the recognizer toward the wake word.
    static let contextualStrings = ["Poyo", "Hey Poyo"]
    static let maxDistance = 1

    private struct Pending { var hitAt: TimeInterval; var finals: [String]; var volatile: String; var changedAt: TimeInterval; var endpointAt: TimeInterval? = nil }
    private struct State { var pending: Pending?; var swallowFinalUntil: TimeInterval? }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {}

    var isListeningForCommand: Bool { state.withLock { $0.pending != nil || $0.swallowFinalUntil != nil } }

    /// The request around the wake word in `text`, or nil: the words after it, or, when it ends the sentence
    /// ("Can you save him to my contacts, Poyo?"), the words before it. Exact "poyo" counts anywhere; aliases and
    /// near misses (one edit, 4–5 letters, starting with p or b) only in the first three words.
    static func find(in text: String) -> String? {
        let cleaned = text.lowercased().replacingOccurrences(of: "[^a-z' ]+", with: " ", options: .regularExpression)
        let tokens = cleaned.split(separator: " ").map(String.init)
        func request(before i: Int, after j: Int) -> String {
            let after = tokens[j...].joined(separator: " ")
            guard after.isEmpty else { return after }
            let before = tokens[..<i].drop { fillers.contains($0) }
            return before.allSatisfy { fillers.contains($0) } ? "" : before.joined(separator: " ")
        }
        for (i, tok) in tokens.enumerated() {
            let stripped = tok.replacingOccurrences(of: "'s$", with: "", options: .regularExpression)
            if stripped == target { return request(before: i, after: i + 1) }
            guard i < 3 else { continue }
            if aliases.contains(tok) || aliases.contains(stripped) { return request(before: i, after: i + 1) }
            if (4...5).contains(stripped.count), let c = stripped.first, c == "p" || c == "b", levenshtein(stripped, target) <= maxDistance {
                return request(before: i, after: i + 1)
            }
            if i + 1 < tokens.count, twoWordAliases.contains("\(tok) \(tokens[i + 1])") {
                return request(before: i, after: i + 2)
            }
        }
        return nil
    }

    static let fillers: Set<String> = ["hey", "hi", "ok", "okay", "yo", "so", "um", "uh", "oh", "and"]

    func feed(text: String, isFinal: Bool, t: TimeInterval) {
        var emit: WakeWordHit?
        state.withLock { s in
            if let until = s.swallowFinalUntil {
                // The utterance already went out from its volatile text; drop its revisions and its final.
                if t > until { s.swallowFinalUntil = nil } else {
                    if isFinal { s.swallowFinalUntil = nil }
                    return
                }
            }
            if var p = s.pending {
                if t - p.hitAt > collectWindow {
                    emit = WakeWord.hit(p, at: t)
                    s.pending = nil
                    return
                }
                let body = WakeWord.find(in: text) ?? text
                if isFinal {
                    p.finals.append(body); p.volatile = ""
                    if !WakeWord.combined(p).isEmpty {
                        emit = WakeWord.hit(p, at: t)
                        s.pending = nil
                        return
                    }
                } else if body != p.volatile {
                    p.volatile = body; p.changedAt = t
                }
                s.pending = p
                return
            }
            guard let remainder = WakeWord.find(in: text) else { return }
            if isFinal, !remainder.isEmpty {
                emit = WakeWordHit(text: remainder, command: CommandParser.parse(remainder), t: t)
            } else {
                s.pending = Pending(hitAt: t, finals: [], volatile: isFinal ? "" : remainder, changedAt: t)
            }
        }
        if let emit { onHit?(emit) }
    }

    /// Speech stopped at `t` (the recognizer's detector): a pending request is flushed as soon as its text holds
    /// still for `endpointSettle`, instead of the full `settle`.
    func endpoint(at t: TimeInterval) {
        state.withLock { s in
            guard var p = s.pending, !p.volatile.isEmpty else { return }
            p.endpointAt = t
            s.pending = p
        }
    }

    /// Emits settled volatile text and flushes an expired collection (call about every 0.1 s).
    func tick(now: TimeInterval) {
        let emit: WakeWordHit? = state.withLock { s in
            guard let p = s.pending else { return nil }
            if now - p.hitAt > collectWindow {
                s.pending = nil
                return WakeWord.hit(p, at: now)
            }
            let needed = p.endpointAt.map { $0 >= p.changedAt - 0.5 } == true ? endpointSettle : settle
            guard !p.volatile.isEmpty, now - p.changedAt >= needed else { return nil }
            s.pending = nil
            s.swallowFinalUntil = now + 6
            return WakeWord.hit(p, at: now)
        }
        if let emit { onHit?(emit) }
    }

    private static func combined(_ p: Pending) -> String { (p.finals + [p.volatile]).joined(separator: " ").trimmingCharacters(in: .whitespaces) }

    private static func hit(_ p: Pending, at t: TimeInterval) -> WakeWordHit {
        let text = combined(p)
        return WakeWordHit(text: text, command: CommandParser.parse(text), t: t)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
