import Foundation
import QuartzCore
import os

/// Watches recognizer text for "familiar" (Levenshtein ≤ 2, plus common mishearings), then collects up to
/// `collectWindow` seconds of following text and hands it to `CommandParser`.
final class WakeWord: @unchecked Sendable {
    var collectWindow: TimeInterval = 4
    var onHit: ((WakeWordHit) -> Void)?

    static let target = "familiar"
    static let aliases: Set<String> = ["familiar", "familia", "familiar's", "familiars", "familier", "famillia", "the miller", "familiar,"]
    static let maxDistance = 2

    private struct Pending { var hitAt: TimeInterval; var finals: [String]; var volatile: String }
    private let state = OSAllocatedUnfairLock(initialState: Optional<Pending>.none)

    init() {}

    var isListeningForCommand: Bool { state.withLock { $0 != nil } }

    /// Position of the wake word in `text` and the remainder after it, or nil.
    static func find(in text: String) -> String? {
        let cleaned = text.lowercased().replacingOccurrences(of: "[^a-z' ]+", with: " ", options: .regularExpression)
        let tokens = cleaned.split(separator: " ").map(String.init)
        for (i, tok) in tokens.enumerated() {
            let stripped = tok.replacingOccurrences(of: "'s$", with: "", options: .regularExpression)
            if aliases.contains(tok) || aliases.contains(stripped) || (stripped.count >= 6 && levenshtein(stripped, target) <= maxDistance) {
                return tokens[(i + 1)...].joined(separator: " ")
            }
            if i + 1 < tokens.count, aliases.contains("\(tok) \(tokens[i + 1])") {
                return tokens[(i + 2)...].joined(separator: " ")
            }
        }
        return nil
    }

    func feed(text: String, isFinal: Bool, t: TimeInterval) {
        var emit: WakeWordHit?
        state.withLock { pending in
            if var p = pending {
                if t - p.hitAt > collectWindow {
                    emit = WakeWord.hit(p, at: t)
                    pending = nil
                    return
                }
                let body = WakeWord.find(in: text) ?? text
                if isFinal { p.finals.append(body); p.volatile = "" } else { p.volatile = body }
                if isFinal, let c = CommandParser.parse(WakeWord.combined(p)) {
                    emit = WakeWordHit(text: WakeWord.combined(p), command: c, t: t)
                    pending = nil
                } else {
                    pending = p
                }
                return
            }
            guard let remainder = WakeWord.find(in: text) else { return }
            var p = Pending(hitAt: t, finals: [], volatile: "")
            if isFinal { p.finals = [remainder] } else { p.volatile = remainder }
            if isFinal, let c = CommandParser.parse(remainder) {
                emit = WakeWordHit(text: remainder, command: c, t: t)
            } else {
                pending = p
            }
        }
        if let emit { onHit?(emit) }
    }

    /// Flushes a pending collection once the window has elapsed (call periodically from a timer).
    func tick(now: TimeInterval) {
        let emit: WakeWordHit? = state.withLock { pending in
            guard let p = pending, now - p.hitAt > collectWindow else { return nil }
            pending = nil
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
