import Foundation
import os

// Quick facts: the wearer hears "the Longhorns game" or "Tacodeli" in a conversation and asks Poyo what it is, or
// says "Poyo, look up HackTX", and gets one spoken line from a Google search through SerpApi. Text only: the words
// the wearer asked about leave the phone, never a frame, the transcript, a location or a person's name.

/// One fact, already condensed to a spoken line.
struct QuickFact: Equatable {
    let text: String
    /// Which part of the result page it came from: answer, weather, sports, knowledge, web.
    let source: String
}

protocol QuickFactSource: AnyObject {
    var isConfigured: Bool { get }
    func lookup(_ query: String) async throws -> QuickFact?
}

extension Phrasebook {
    static let searchUnavailable = "Search isn't set up."
    static let searchFailed = "I couldn't reach search."
    static let nothingFound = "I couldn't find anything on that."
    static let noPeopleLookups = "I don't look people up."
}

/// SerpApi's Google engine (`GET https://serpapi.com/search.json`). One ephemeral session, 6 s timeout, SafeSearch on.
final class SerpApiClient: QuickFactSource, @unchecked Sendable {
    enum ClientError: LocalizedError, Equatable {
        case missingKey
        case http(Int)
        case malformed
        var errorDescription: String? {
            switch self {
            case .missingKey: return "SERPAPI_KEY is not configured."
            case let .http(code): return "SerpApi returned HTTP \(code)."
            case .malformed: return "SerpApi returned an unexpected payload."
            }
        }
    }

    static let endpoint = URL(string: "https://serpapi.com/search.json")!
    let apiKey: String?
    let session: URLSession
    var timeout: TimeInterval = 6

    init(apiKey: String?, session: URLSession = SerpApiClient.makeSession()) {
        self.apiKey = apiKey
        self.session = session
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }

    /// Only the query, the engine and the key go out; no location, no device fields.
    func request(for query: String) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.missingKey }
        var comps = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "engine", value: "google"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "us"),
            URLQueryItem(name: "num", value: "5"),
            URLQueryItem(name: "safe", value: "active"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: timeout)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    func lookup(_ query: String) async throws -> QuickFact? {
        let (data, response) = try await session.data(for: request(for: query))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.malformed }
        return Self.fact(from: root)
    }

    // MARK: Parsing

    /// Best single line on the page: answer box → live game → knowledge panel → first web snippet.
    static func fact(from root: [String: Any]) -> QuickFact? {
        if let box = root["answer_box"] as? [String: Any], let a = answerLine(box) { return QuickFact(text: a.text, source: a.source) }
        if let sports = root["sports_results"] as? [String: Any], let line = sportsLine(sports) { return QuickFact(text: line, source: "sports") }
        if let kg = root["knowledge_graph"] as? [String: Any], let line = knowledgeLine(kg) { return QuickFact(text: line, source: "knowledge") }
        for r in (root["organic_results"] as? [[String: Any]]) ?? [] {
            if let s = r["snippet"] as? String, let line = spoken(s) { return QuickFact(text: line, source: "web") }
        }
        return nil
    }

    static func answerLine(_ box: [String: Any]) -> (text: String, source: String)? {
        if box["type"] as? String == "weather_result" {
            guard let temp = box["temperature"] as? String else { return nil }
            let unit = (box["unit"] as? String) == "Celsius" ? "Celsius" : "Fahrenheit"
            let place = (box["location"] as? String).map { "\($0): " } ?? ""
            let sky = (box["weather"] as? String).map { ", \($0.lowercased())" } ?? ""
            return spoken("\(place)\(temp) degrees \(unit)\(sky).").map { (text: $0, source: "weather") }
        }
        if let defs = box["definitions"] as? [String], let first = defs.first, let line = spoken(first) {
            let word = (box["syllables"] as? String)?.replacingOccurrences(of: "·", with: "") ?? ""
            return (text: word.isEmpty ? line : "\(word): \(line)", source: "answer")
        }
        if let answer = box["answer"] as? String, let line = spoken(answer) {
            // Short answers ("330 m") need their subject ("Eiffel Tower, height").
            if line.split(separator: " ").count < 4, let title = (box["title"] as? String).flatMap({ spoken($0, maxWords: 10) }) {
                return (text: "\(title.dropLast()) \(line)", source: "answer")
            }
            return (text: line, source: "answer")
        }
        if let result = box["result"] as? String, let line = spoken(result) { return (text: line, source: "answer") }
        if let snippet = box["snippet"] as? String, let line = spoken(snippet) { return (text: line, source: "answer") }
        if let list = box["list"] as? [String], let line = spoken(list.prefix(4).joined(separator: ", ")) { return (text: line, source: "answer") }
        return nil
    }

    /// "Ole Miss Rebels 27, Texas Longhorns 34, final." / "Texas Longhorns versus Ole Miss Rebels, Saturday 6:30 PM."
    static func sportsLine(_ sports: [String: Any]) -> String? {
        let game = (sports["game_spotlight"] as? [String: Any]) ?? (sports["games"] as? [[String: Any]])?.first
        guard let game, let teams = game["teams"] as? [[String: Any]], teams.count == 2 else { return nil }
        let names = teams.map { ($0["name"] as? String) ?? "unknown team" }
        let totals: [String?] = teams.map { team in
            if let s = team["score"] as? String { return s }
            if let score = team["score"] as? [String: Any], let t = score["T"] { return "\(t)" }
            return nil
        }
        let status = (game["status"] as? String) ?? ""
        let date = (game["date"] as? String) ?? ""
        if let a = totals[0], let b = totals[1] {
            let when = status.lowercased().hasPrefix("final") ? "final" : (status.isEmpty ? date : status)
            return spoken("\(names[0]) \(a), \(names[1]) \(b)\(when.isEmpty ? "" : ", \(when)").")
        }
        return spoken("\(names[0]) versus \(names[1])\(date.isEmpty ? "" : ", \(date)").")
    }

    /// "Tacodeli, taco restaurant. Mexican-inspired tacos across Texas."
    static func knowledgeLine(_ kg: [String: Any]) -> String? {
        guard let title = kg["title"] as? String, !title.isEmpty else { return nil }
        let type = (kg["type"] as? String).map { ", \($0.lowercased())" } ?? ""
        let description = (kg["description"] as? String).flatMap { spoken($0, maxWords: 18) } ?? ""
        guard !type.isEmpty || !description.isEmpty else { return nil }
        return spoken("\(title)\(type). \(description)")
    }

    /// Search-page prose as one spoken line: no ellipses, no "Oct 24, 2026 —" date prefix, the first sentence or
    /// two, at most `maxWords` words.
    static func spoken(_ raw: String, maxWords: Int = 24) -> String? {
        var t = raw.replacingOccurrences(of: "…", with: " ").replacingOccurrences(of: "...", with: " ")
        t = t.replacingOccurrences(of: "^\\s*[A-Z][a-z]{2,8}\\.? \\d{1,2}, \\d{4} [—–-] ", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_#`\\[\\]]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let sentences = t.replacingOccurrences(of: "([.!?])\\s+", with: "$1\n", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var kept: [String] = []
        var count = 0
        for s in sentences {
            kept.append(s)
            count += s.split(separator: " ").count
            if count >= 6 { break }
        }
        var words = kept.joined(separator: " ").split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        if words.count > maxWords { words = Array(words.prefix(maxWords)) }
        var line = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:- "))
        guard let first = line.first else { return nil }
        line = first.uppercased() + line.dropFirst()
        if let last = line.last, !".!?".contains(last) { line += "." }
        return line
    }
}

/// The rules around a lookup, kept apart from the HTTP client so tests run them without a network: only what the
/// wearer asked for is searched, never a saved person's name or the wearer's own.
final class QuickFacts: @unchecked Sendable {
    enum Outcome: Equatable {
        case fact(QuickFact)
        case refused        // the query names a person
        case nothing        // the page had nothing worth saying
        case unavailable    // no SERPAPI_KEY
        case failed         // network or HTTP error
    }

    let source: QuickFactSource
    private let blockedNames: () -> [String]
    private let log = Logger(subsystem: "familiar", category: "facts")

    init(source: QuickFactSource, blockedNames: @escaping () -> [String] = { [] }) {
        self.source = source
        self.blockedNames = blockedNames
    }

    var isConfigured: Bool { source.isConfigured }

    func answer(_ raw: String) async -> Outcome {
        guard let query = Self.cleanQuery(raw) else { return .nothing }
        guard isConfigured else { return .unavailable }
        guard !Self.mentionsPerson(query, names: blockedNames()) else { return .refused }
        do {
            guard let fact = try await source.lookup(query) else { return .nothing }
            return .fact(fact)
        } catch {
            log.error("lookup failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    static func phrase(_ outcome: Outcome) -> String {
        switch outcome {
        case let .fact(f): return f.text
        case .refused: return Phrasebook.noPeopleLookups
        case .nothing: return Phrasebook.nothingFound
        case .unavailable: return Phrasebook.searchUnavailable
        case .failed: return Phrasebook.searchFailed
        }
    }

    private static let askingWords = "^(?:(?:hey|ok|okay|so|um|uh|please|can you|could you|would you)\\s+)*(?:(?:look|search|google)(?:\\s+(?:up|for))?|tell me(?:\\s+about)?|find(?:\\s+out)?(?:\\s+about)?|what(?:'s| is| are| was| were)|what do you know about)\\s+"
    private static let searchVerbs = "^(?:(?:hey|ok|okay|so|um|uh|please|can you|could you|would you) )*(?:look up|search(?: for| up)?|google|what does .+ mean|who won\\b|what(?:'s| is) the (?:score|weather|forecast|time|date|price)\\b)"

    /// Strips the asking words ("Poyo, look up", "what is", the "?") and keeps the subject as the wearer said it.
    static func cleanQuery(_ raw: String) -> String? {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        q = q.replacingOccurrences(of: "\\bpoyo\\b[,!.]?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        q = q.replacingOccurrences(of: askingWords, with: "", options: [.regularExpression, .caseInsensitive])
        q = q.replacingOccurrences(of: "[?!.,]+$", with: "", options: .regularExpression)
        q = q.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, q.range(of: "[a-z0-9]", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        guard !["it", "that", "this", "it up", "that up", "them", "him", "her"].contains(q.lowercased()) else { return nil }
        return q
    }

    /// Only an outright request to search runs without the model ("look up …", "search for …", "google …",
    /// "who won …", "what's the score/weather …"). "What's that?" needs the conversation to resolve "that", so it
    /// goes to the model, which answers with a `lookup` action and a query.
    static func explicitQuery(in phrase: String) -> String? {
        let s = CommandParser.normalize(WakeWord.find(in: phrase) ?? phrase)
        guard s.range(of: searchVerbs, options: .regularExpression) != nil else { return nil }
        return cleanQuery(phrase)
    }

    /// True when any word (3+ letters) of a blocked name appears in the query.
    static func mentionsPerson(_ query: String, names: [String]) -> Bool {
        let q = CommandParser.normalize(query)
        for name in names {
            for part in name.split(separator: " ") {
                let word = CommandParser.normalize(String(part))
                guard word.count >= 3 else { continue }
                if q.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil { return true }
            }
        }
        return false
    }
}
