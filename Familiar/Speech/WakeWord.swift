import Foundation
import QuartzCore
import os

/// Watches recognizer text for "Poyo" (plus common mishearings), then hands the request that follows to
/// `CommandParser` / the assistant as soon as it is complete:
/// - a final segment with text after the wake word emits at once, parsed or not;
/// - in-progress (volatile) text that looks complete emits once it has not changed for `settle` seconds, or
///   `endpointSettle` seconds after the recognizer's voice-activity detector said speech stopped (`endpoint(at:)`);
///   text that looks cut off ("can you", "change to") waits `incompleteSettle` instead;
/// - the final that later arrives for an utterance that went out early is swallowed, unless it says more: then a
///   correction hit with the full request supersedes the early one (the brain cancels the answer in flight);
/// - a bare "Poyo." waits up to `collectWindow` seconds for the request to start; nothing waits past `maxCollect`.
final class WakeWord: @unchecked Sendable {
    var collectWindow: TimeInterval = 4
    var maxCollect: TimeInterval = 8
    var settle: TimeInterval = 0.5
    /// After speech stopped, how long the volatile text must hold still (the recognizer finishes the words it
    /// already heard a beat later).
    var endpointSettle: TimeInterval = 0.25
    /// A request whose last word says more is coming ("Poyo, can you…") waits this long before it goes out anyway.
    var incompleteSettle: TimeInterval = 1.5
    var onHit: ((WakeWordHit) -> Void)?

    static let target = "poyo"
    static let aliases: Set<String> = ["poyo", "poyos", "poyo's", "pollo", "poio", "poyoh", "boyo", "pojo", "poyo,"]
    static let twoWordAliases: Set<String> = ["po yo", "poe yo", "pull yo", "bo yo", "poh yo"]
    /// Biases the recognizer toward the wake word.
    static let contextualStrings = ["Poyo", "Hey Poyo"]
    static let maxDistance = 1

    private struct Pending { var hitAt: TimeInterval; var finals: [String]; var volatile: String; var changedAt: TimeInterval; var endpointAt: TimeInterval? = nil }
    private struct Early { let text: String; let command: Command? }
    private struct State { var pending: Pending?; var swallowFinalUntil: TimeInterval?; var early: Early? }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {}

    var isListeningForCommand: Bool { state.withLock { $0.pending != nil || $0.swallowFinalUntil != nil } }

    /// The request around the wake word in `text`, or nil: the words after it, or, when it ends the sentence
    /// ("Can you save him to my contacts, Poyo?"), the words before it. Exact "poyo" counts anywhere; aliases and
    /// near misses (one edit, 4–5 letters, starting with p or b) only in the first three words. "Poyo, Poyo, …"
    /// is one wake word.
    static func find(in text: String) -> String? {
        let cleaned = text.lowercased().replacingOccurrences(of: "[^a-z' ]+", with: " ", options: .regularExpression)
        let tokens = cleaned.split(separator: " ").map(String.init)
        func isWake(_ tok: String) -> Bool {
            let stripped = tok.replacingOccurrences(of: "'s$", with: "", options: .regularExpression)
            return stripped == target || aliases.contains(tok) || aliases.contains(stripped)
        }
        func request(before i: Int, after j: Int) -> String {
            var k = j
            while k < tokens.count, isWake(tokens[k]) { k += 1 }
            let after = tokens[k...].joined(separator: " ")
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

    /// Last words after which the sentence is still coming: "Poyo, can you…", "change to…", "what was that I…".
    static let danglingWords: Set<String> = ["a", "an", "the", "to", "of", "in", "on", "at", "for", "with", "from", "and", "or", "but", "if", "is", "are", "was", "were", "be", "can", "could", "would", "should", "will", "do", "does", "did", "what", "where", "who", "which", "how", "when", "why", "i", "you", "my", "your", "his", "her", "their", "its", "me", "him", "them", "it's", "that's", "there's", "what's", "where's", "who's", "please", "um", "uh", "like", "so", "about", "into", "than", "then", "as", "by", "very", "really", "just", "not", "hey"]

    /// Whether in-progress text can go out as the request: a known command always; otherwise at least two words
    /// and a last word that does not promise more.
    static func looksComplete(_ text: String) -> Bool {
        if CommandParser.parse(text) != nil { return true }
        let words = CommandParser.normalize(text).split(separator: " ")
        guard words.count >= 2, let last = words.last else { return false }
        return !danglingWords.contains(String(last))
    }

    /// The full request when `final` is the finished form of a request that went out early as `early`
    /// ("can you" → "can you update his name"); nil when it says nothing more.
    static func correction(of early: String, from final: String) -> String? {
        let full = find(in: final) ?? final
        let a = CommandParser.normalize(early), b = CommandParser.normalize(full)
        guard !a.isEmpty, b.count > a.count, b.hasPrefix(a) else { return nil }
        return full
    }

    func feed(text: String, isFinal: Bool, t: TimeInterval) {
        var emit: WakeWordHit?
        state.withLock { s in
            if let until = s.swallowFinalUntil {
                // The utterance already went out from its volatile text; drop its revisions and its final, unless
                // the final says more than what went out: then correct it.
                if t > until { s.swallowFinalUntil = nil; s.early = nil } else {
                    guard isFinal else { return }
                    s.swallowFinalUntil = nil
                    if let early = s.early, let full = WakeWord.correction(of: early.text, from: text) {
                        let command = CommandParser.parse(full)
                        if early.command == nil || command != early.command { emit = WakeWordHit(text: full, command: command, t: t, isCorrection: true) }
                    }
                    s.early = nil
                    return
                }
            }
            if var p = s.pending {
                if t - max(p.hitAt, p.changedAt) > collectWindow || t - p.hitAt > maxCollect {
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
            let text = WakeWord.combined(p)
            if text.isEmpty || now - p.hitAt > maxCollect {
                // A bare "Poyo." waits for the request to start; nothing waits forever.
                guard now - p.hitAt > (text.isEmpty ? collectWindow : maxCollect) else { return nil }
                s.pending = nil
                return WakeWord.hit(p, at: now)
            }
            let quiet = now - p.changedAt
            let afterEndpoint = p.endpointAt.map { $0 >= p.changedAt - 0.5 } == true
            let needed = WakeWord.looksComplete(text) ? (afterEndpoint ? endpointSettle : settle) : incompleteSettle
            guard quiet >= needed else { return nil }
            s.pending = nil
            // It went out from in-progress text: its final is still to come (swallowed, or a correction).
            let hit = WakeWord.hit(p, at: now)
            s.swallowFinalUntil = now + 6
            s.early = Early(text: hit.text, command: hit.command)
            return hit
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
