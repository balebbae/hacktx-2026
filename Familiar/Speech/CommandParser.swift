import Foundation
import QuartzCore

/// Pure regex grammar from spoken text to `Command`. Unknown text → nil (the router says "Sorry, I didn't get that.").
enum CommandParser {
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        s = s.replacingOccurrences(of: "[^a-z0-9' ]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func match(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    private static func name(_ raw: String) -> String? {
        var n = raw.replacingOccurrences(of: "\\b(please|now|for me)\\b", with: "", options: .regularExpression)
        n = n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= 40, !["them", "him", "her", "me", "it", "someone", "somebody"].contains(n) else { return nil }
        return n.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func parse(_ text: String) -> Command? {
        let s = normalize(text)
        guard !s.isEmpty else { return nil }

        if match("\\b(unmute|un mute|start talking|talk again|speak again)\\b", in: s) != nil { return .unmute }
        if match("\\b(mute|stop talking|be quiet|shut up|hush)\\b", in: s) != nil { return .mute }

        if let m = match("\\b(quiet|normal|chatty) mode\\b", in: s) ?? match("\\b(?:go|be|set to|switch to|set|make it|make yourself)\\s+(quiet|normal|chatty)\\b", in: s) {
            switch m[1] { case "quiet": return .setMode(.quiet); case "chatty": return .setMode(.chatty); default: return .setMode(.normal) }
        }

        if match("\\b(who'?s|who is|whos) (here|around|there|near ?by|with me|in front of me)\\b", in: s) != nil
            || match("\\b(anyone|anybody|who do you see|who can you see|who's that|who is that)\\b", in: s) != nil { return .whoIsHere }

        if match("\\b(remember|save|add) (them|him|her|this person|that person|this one|this guy|this girl|this lady|this man|this woman)\\b", in: s) != nil
            || match("\\bremember (their|his|her) face\\b", in: s) != nil { return .rememberThem }

        if match("\\b(say that again|say again|repeat that|repeat|come again|what did you say|one more time|again)\\b", in: s) != nil { return .repeatLast }

        if match("\\b(cancel|never mind|nevermind|forget it|stop)\\b", in: s) != nil { return .cancel }

        if let m = match("\\b(?:where is|where's|wheres|where did|find) (.+?)(?: go| at| now)?$", in: s), let n = name(m[1]) { return .whereIs(n) }
        if let m = match("\\b(?:call|phone|dial|ring) (.+)$", in: s), let n = name(m[1]) { return .call(n) }
        if let m = match("\\b(?:text|message|send a (?:text|message) to|send (?:a )?text to) (.+)$", in: s), let n = name(m[1]) { return .text(n) }

        return nil
    }
}

/// Publishes parsed commands from the wake word; `hits` carries unparsed text too for the router's apology.
final class WakeWordCommandSource: CommandSource, @unchecked Sendable {
    let wakeWord: WakeWord
    private let bus = EventBus<Command>()
    private let hitBus = EventBus<WakeWordHit>()
    private var tasks: [Task<Void, Never>] = []

    init(wakeWord: WakeWord = WakeWord()) {
        self.wakeWord = wakeWord
        wakeWord.onHit = { [weak self] hit in
            self?.hitBus.publish(hit)
            if let c = hit.command { self?.bus.publish(c) }
        }
    }

    func subscribe() -> AsyncStream<Command> { bus.subscribe() }
    func subscribeHits() -> AsyncStream<WakeWordHit> { hitBus.subscribe() }

    // S8 — "Familiar, …" phrases the parser did not recognise fall through to the conversational agent.
    // Recognised commands keep flowing through `subscribe()` untouched; the agent never sees them.
    func subscribeUnparsed() -> AsyncStream<String> {
        let hits = hitBus.subscribe()
        return AsyncStream { cont in
            let t = Task {
                for await h in hits where h.command == nil {
                    let text = h.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { cont.yield(text) }
                }
                cont.finish()
            }
            cont.onTermination = { _ in t.cancel() }
        }
    }

    /// Feeds finals (and volatile text when the transcriber offers it) into the wake word and runs its 4 s timer.
    func attach(_ transcriber: Transcriber) {
        let finals = transcriber.subscribe()
        tasks.append(Task.detached { [weak self] in
            for await seg in finals where seg.isFinal { self?.wakeWord.feed(text: seg.text, isFinal: true, t: seg.end) }
        })
        if let volatile = (transcriber as? VolatileTextSource)?.subscribeVolatile() {
            tasks.append(Task.detached { [weak self] in
                for await v in volatile { self?.wakeWord.feed(text: v.text, isFinal: false, t: v.t) }
            })
        }
        tasks.append(Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.wakeWord.tick(now: CACurrentMediaTime())
            }
        })
    }

    func detach() { tasks.forEach { $0.cancel() }; tasks.removeAll() }
}
