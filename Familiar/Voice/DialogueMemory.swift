import Foundation
import os

/// What has been said between the wearer and Poyo lately, whichever lane produced the line. A people cue, a path
/// alert, a command reply and a model answer are all Poyo's turns; a "Poyo, …" request is the wearer's. The model
/// gets them as proper chat turns, so "where did he go?" after "Marcus left." resolves and Poyo does not repeat
/// what the app just said; "say that again" has something to repeat. Kept in RAM only; turns expire after `maxAge`.
final class DialogueMemory: @unchecked Sendable {
    enum Role: String, Equatable { case wearer, poyo }
    struct Turn: Equatable { let role: Role; let text: String; let t: TimeInterval }

    var maxTurns = 12
    var maxAge: TimeInterval = 300
    /// The brain records its answer when it starts playing and the speaker reports the same line when it has played:
    /// the same text from the same role within this long is one turn.
    var dedupeWindow: TimeInterval = 10
    private let lock = OSAllocatedUnfairLock(initialState: [Turn]())

    init() {}

    func record(_ role: Role, _ text: String, at t: TimeInterval) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        lock.withLock { turns in
            if let last = turns.last, last.role == role, last.text == line, t - last.t <= dedupeWindow { return }
            turns.append(Turn(role: role, text: line, t: t))
            turns.removeAll { t - $0.t > maxAge }
            if turns.count > maxTurns { turns.removeFirst(turns.count - maxTurns) }
        }
    }

    /// The last `limit` turns no older than `maxAge`, oldest first.
    func turns(now: TimeInterval, limit: Int = 8) -> [Turn] {
        lock.withLock { turns in Array(turns.filter { now - $0.t <= maxAge }.suffix(limit)) }
    }

    /// Poyo's last line, for "say that again".
    func lastPoyoLine(now: TimeInterval) -> String? { turns(now: now, limit: maxTurns).last { $0.role == .poyo }?.text }

    func clear() { lock.withLock { $0.removeAll() } }

    /// Chat messages for the model. Consecutive turns of one role merge into one message, so user and assistant
    /// alternate the way chat APIs expect.
    static func messages(_ turns: [Turn]) -> [(role: String, text: String)] {
        var out: [(role: String, text: String)] = []
        for t in turns {
            let role = t.role == .wearer ? "user" : "assistant"
            if let last = out.last, last.role == role { out[out.count - 1].text += " " + t.text } else { out.append((role, t.text)) }
        }
        return out
    }
}
