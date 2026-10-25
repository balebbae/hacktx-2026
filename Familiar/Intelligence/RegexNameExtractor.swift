import Foundation

/// Cheap, instant name extraction from `other`-attributed segments. Confidence 0.9 for "my name is" / "I'm",
/// 0.7 for the other patterns. Stop list filters greetings and the user's own name.
struct RegexNameExtractor: NameExtractor {
    static let strongPattern = try! NSRegularExpression(pattern: #"\b(?:I'm|I am|[Mm]y name is)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)"#)
    static let weakPattern = try! NSRegularExpression(pattern: #"\b(?:[Tt]his is|[Ii]t's|[Cc]all me)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)"#)
    static let herePattern = try! NSRegularExpression(pattern: #"\b([A-Z][a-z]+) here\b"#)
    static let stopList: Set<String> = ["hi", "hey", "hello", "nice", "okay", "ok", "yes", "no", "sorry", "thanks", "thank", "good", "sure", "fine", "great", "so", "just", "not", "here", "there", "glad", "happy", "really", "very", "also", "still", "back", "done", "building", "working", "going", "doing", "from", "at", "in", "on", "the", "a", "an", "all", "well"]

    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess {
        Self.guess(segments: segments, userName: userName)
    }

    static func guess(segments: [TranscriptSegment], userName: String) -> NameGuess {
        var best = NameGuess(name: nil, confidence: 0, source: "regex")
        for seg in segments where seg.speaker == .other {
            for (pattern, confidence) in [(strongPattern, 0.9), (weakPattern, 0.7), (herePattern, 0.7)] {
                for candidate in matches(pattern, in: seg.text) {
                    guard let cleaned = clean(candidate, userName: userName) else { continue }
                    if confidence > best.confidence { best = NameGuess(name: cleaned, confidence: confidence, source: "regex") }
                }
            }
        }
        return best
    }

    /// True when the text looks like an introduction; used by `NameGuessCache` to decide when to refresh.
    static func looksLikeIntroduction(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return [strongPattern, weakPattern, herePattern].contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// For the "What should I call you?" reply: "Marcus", "It's Marcus", "Marcus Lee", "call me Marc".
    static func nameFromDirectReply(_ text: String, userName: String) -> String? {
        let seg = TranscriptSegment(text: text, start: 0, end: 0, isFinal: true, speaker: .other)
        if let n = guess(segments: [seg], userName: userName).name { return n }
        let words = text.split { !$0.isLetter && $0 != "'" && $0 != "-" }.map(String.init)
        let candidates = words.filter { w in !stopList.contains(w.lowercased()) && w.lowercased() != userName.lowercased() }
        guard (1...2).contains(candidates.count) else { return nil }
        return candidates.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func clean(_ raw: String, userName: String) -> String? {
        var words = raw.split(separator: " ").map(String.init)
        words = words.filter { !stopList.contains($0.lowercased()) }
        guard let first = words.first, first.count >= 2 else { return nil }
        if first.lowercased() == userName.lowercased() { return nil }
        if words.count == 2, let second = words.last, second.lowercased() == userName.lowercased() { words.removeLast() }
        return words.joined(separator: " ")
    }
}

/// Word-boundary yes / no rules. "I know" must not be a "no"; "Yes, sure." is a yes.
struct RulesYesNoClassifier: YesNoClassifier {
    static let yesPhrases = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok", "of course", "go ahead", "fine", "absolutely", "that's fine", "thats fine", "sounds good", "please do", "yes please"]
    static let noPhrases = ["no", "nope", "nah", "rather not", "don't", "dont", "i'd rather not", "no thanks", "not really", "please don't", "no way", "never"]

    func classify(_ reply: String) async -> YesNo { Self.classify(reply) }

    static func classify(_ reply: String) -> YesNo {
        let normalized = " " + reply.lowercased().replacingOccurrences(of: "’", with: "'").map { $0.isLetter || $0 == "'" ? String($0) : " " }.joined().split(separator: " ").joined(separator: " ") + " "
        let yesHit = yesPhrases.contains { normalized.contains(" \($0) ") }
        let noHit = noPhrases.contains { normalized.contains(" \($0) ") }
        switch (yesHit, noHit) {
        case (true, false): return .yes
        case (false, true): return .no
        case (true, true):
            // "no, that's fine" / "yeah, no" — the later word usually wins; fall back to unclear when truly mixed.
            let yesIdx = yesPhrases.compactMap { normalized.range(of: " \($0) ")?.lowerBound }.min()
            let noIdx = noPhrases.compactMap { normalized.range(of: " \($0) ")?.lowerBound }.min()
            if let y = yesIdx, let n = noIdx, normalized.distance(from: y, to: n) != 0 {
                return normalized.hasSuffix(" fine ") || normalized.hasSuffix(" sure ") || normalized.hasSuffix(" okay ") ? .yes : (n > y ? .no : .yes)
            }
            return .unclear
        default: return .unclear
        }
    }
}
