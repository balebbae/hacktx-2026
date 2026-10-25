import Foundation

/// Last check on any model-written line before it is spoken: drops SKIP, the wake word, and any sentence that
/// describes a person (looks, clothes, mood) or mentions the face redaction; caps the length.
enum SpeechSanitizer {
    static let personDetail = try! NSRegularExpression(pattern: "\\b(man|men|woman|women|guy|guys|girl|girls|boy|boys|lady|ladies|gentleman|child|kid|kids|wearing|wears|shirt|jacket|hoodie|dress|hair|beard|blonde|face|faces|blacked|blurred|redacted|masked|black box|black boxes|smiling|frowning|happy|sad|angry|upset|tired|mood)\\b", options: [.caseInsensitive])

    static func clean(_ text: String?, maxWords: Int = 16) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.uppercased().hasPrefix("SKIP") else { return nil }
        t = t.replacingOccurrences(of: "\\bpoyo\\b[,!.]?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "[*_#`]", with: "", options: .regularExpression)
        let sentences = t.replacingOccurrences(of: "([.!?])\\s+", with: "$1\n", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { s in !s.isEmpty && personDetail.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil }
        var words = sentences.joined(separator: " ").split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        if words.count > maxWords { words = Array(words.prefix(maxWords)) }
        var out = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        guard let first = out.first else { return nil }
        out = first.uppercased() + out.dropFirst()
        if let last = out.last, !".!?".contains(last) { out += "." }
        return out
    }
}

/// Wearer speech without the wake word reaches the assistant only when it sounds like a request it can help with.
enum QuestionFilter {
    private static let opener = try! NSRegularExpression(pattern: "^(hey |ok |okay |so |um |uh )?(what|whats|what's|where|wheres|where's|who|whos|who's|how many|how far|how close|which|is there|are there|is that|is this|is it|can you|could you|tell me|describe|read|do you see|any|anything)\\b")

    static func isRequestLike(_ text: String) -> Bool {
        let s = CommandParser.normalize(text)
        guard s.split(separator: " ").count >= 2 else { return false }
        if text.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return true }
        if opener.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return true }
        return s.contains("in front of me") || s.contains("around me")
    }
}
