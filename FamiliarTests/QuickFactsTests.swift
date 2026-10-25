import XCTest
@testable import Familiar

/// Canned facts; no network.
final class FakeQuickFactSource: QuickFactSource, @unchecked Sendable {
    var isConfigured = true
    var facts: [String: QuickFact] = [:]
    var error: Error?
    private(set) var queries: [String] = []
    func lookup(_ query: String) async throws -> QuickFact? {
        queries.append(query)
        if let error { throw error }
        return facts[query]
    }
}

final class QuickFactsTests: XCTestCase {
    private func page(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: Request

    func testRequestIsAGoogleSearchWithOnlyTheQueryAndKey() throws {
        let req = try SerpApiClient(apiKey: "k123").request(for: "Longhorns game")
        let comps = try XCTUnwrap(URLComponents(url: XCTUnwrap(req.url), resolvingAgainstBaseURL: false))
        func q(_ n: String) -> String? { comps.queryItems?.first { $0.name == n }?.value }
        XCTAssertEqual(comps.host, "serpapi.com"); XCTAssertEqual(comps.path, "/search.json")
        XCTAssertEqual(q("engine"), "google"); XCTAssertEqual(q("q"), "Longhorns game"); XCTAssertEqual(q("api_key"), "k123"); XCTAssertEqual(q("safe"), "active")
        XCTAssertNil(q("location")); XCTAssertNil(q("ll"), "no location leaves the phone")
        XCTAssertFalse(SerpApiClient(apiKey: nil).isConfigured)
        XCTAssertFalse(SerpApiClient(apiKey: "").isConfigured)
        XCTAssertThrowsError(try SerpApiClient(apiKey: "").request(for: "x"))
    }

    // MARK: Parsing (shapes captured from real SerpApi responses)

    func testFinishedGameBecomesAScoreLine() {
        let root = page(#"{"sports_results":{"rankings":"10th in SEC","game_spotlight":{"league":"NCAA Football (FBS I)","date":"yesterday, 6:30 PM","status":"Final","teams":[{"name":"Ole Miss Rebels","score":{"1":"3","2":"0","3":"14","4":"10","T":"27"}},{"name":"Texas Longhorns","score":{"1":"10","2":"14","3":"0","4":"10","T":"34"}}]}},"organic_results":[{"title":"Schedule","snippet":"Texas Longhorns Schedule 2026 ; Sat, 10/24."}]}"#)
        XCTAssertEqual(SerpApiClient.fact(from: root), QuickFact(text: "Ole Miss Rebels 27, Texas Longhorns 34, final.", source: "sports"))
    }

    func testUpcomingGameNamesTheTeamsAndTime() {
        let root = page(#"{"sports_results":{"games":[{"date":"Sat, 7:00 PM","teams":[{"name":"Texas Longhorns"},{"name":"Mississippi State Bulldogs"}]}]}}"#)
        XCTAssertEqual(SerpApiClient.fact(from: root)?.text, "Texas Longhorns versus Mississippi State Bulldogs, Sat, 7:00 PM.")
    }

    func testWeatherAnswerBox() {
        let root = page(#"{"answer_box":{"type":"weather_result","temperature":"61","unit":"Fahrenheit","location":"Austin, TX","date":"Sunday 6:00 AM","weather":"Cloudy"},"organic_results":[{"snippet":"Austin, TX 66°F. Tonight: Clear"}]}"#)
        XCTAssertEqual(SerpApiClient.fact(from: root), QuickFact(text: "Austin, TX: 61 degrees Fahrenheit, cloudy.", source: "weather"))
    }

    func testShortAnswerKeepsItsSubject() {
        XCTAssertEqual(SerpApiClient.fact(from: page(#"{"answer_box":{"type":"organic_result","title":"Eiffel Tower / Height","answer":"330 m"}}"#))?.text, "Eiffel Tower / Height 330 m.")
        XCTAssertEqual(SerpApiClient.fact(from: page(#"{"answer_box":{"type":"calculator_result","result":"42"}}"#))?.text, "42.")
        XCTAssertEqual(SerpApiClient.fact(from: page(#"{"answer_box":{"type":"dictionary_results","syllables":"hack·a·thon","definitions":["an event, typically lasting several days, in which a large number of people meet to engage in collaborative computer programming."]}}"#))?.text,
                       "hackathon: An event, typically lasting several days, in which a large number of people meet to engage in collaborative computer programming.")
    }

    func testKnowledgePanelGivesTitleTypeAndDescription() {
        let root = page(#"{"knowledge_graph":{"title":"Tacodeli","type":"Taco restaurant","description":"Mexican-inspired tacos topped with local and organic ingredients. Visit us in Austin, Dallas, Plano and Houston."},"organic_results":[{"snippet":"Tacodeli has award winning Breakfast Tacos."}]}"#)
        XCTAssertEqual(SerpApiClient.fact(from: root), QuickFact(text: "Tacodeli, taco restaurant. Mexican-inspired tacos topped with local and organic ingredients.", source: "knowledge"))
    }

    func testWebSnippetFallbackIsOneCleanSentence() {
        let root = page(#"{"organic_results":[{"title":"HackTX 26 — Freetail Hackers","snippet":"Oct 24, 2026 — Brought to you by a dedicated team of over 60 organizers across six committees, HackTX is a 24-hour hackathon where students from across the country gather in ..."}]}"#)
        XCTAssertEqual(SerpApiClient.fact(from: root), QuickFact(text: "Brought to you by a dedicated team of over 60 organizers across six committees, HackTX is a 24-hour hackathon where students from across the.", source: "web"))
        XCTAssertNil(SerpApiClient.fact(from: page(#"{"search_metadata":{"status":"Success"},"organic_results":[]}"#)))
        XCTAssertNil(SerpApiClient.fact(from: [:]))
    }

    func testSpokenTakesTheFirstSentenceOrTwoAndCapsLength() {
        XCTAssertEqual(SerpApiClient.spoken("Yes. It is open until 3 PM today. Closed Monday."), "Yes. It is open until 3 PM today.")
        XCTAssertEqual(SerpApiClient.spoken("**bold** text … here"), "Bold text here.")
        let long = Array(repeating: "word", count: 40).joined(separator: " ")
        XCTAssertEqual(SerpApiClient.spoken(long)?.split(separator: " ").count, 24)
        XCTAssertNil(SerpApiClient.spoken("   "))
    }

    // MARK: Query rules

    func testCleanQueryStripsTheAskingWords() {
        XCTAssertEqual(QuickFacts.cleanQuery("Poyo, look up the Longhorns game?"), "the Longhorns game")
        XCTAssertEqual(QuickFacts.cleanQuery("what is a hackathon"), "a hackathon")
        XCTAssertEqual(QuickFacts.cleanQuery("search for Tacodeli"), "Tacodeli")
        XCTAssertEqual(QuickFacts.cleanQuery("google HackTX 2026"), "HackTX 2026")
        XCTAssertEqual(QuickFacts.cleanQuery("who won the Longhorns game"), "who won the Longhorns game")
        XCTAssertNil(QuickFacts.cleanQuery("look it up"))
        XCTAssertNil(QuickFacts.cleanQuery("what is that?"))
        XCTAssertNil(QuickFacts.cleanQuery("?"))
    }

    func testExplicitQueryOnlyForOutrightSearchRequests() {
        XCTAssertEqual(QuickFacts.explicitQuery(in: "look up the Longhorns game"), "the Longhorns game")
        XCTAssertEqual(QuickFacts.explicitQuery(in: "Poyo, google Tacodeli"), "Tacodeli")
        XCTAssertEqual(QuickFacts.explicitQuery(in: "what's the score of the Longhorns game"), "the score of the Longhorns game")
        XCTAssertEqual(QuickFacts.explicitQuery(in: "what does hackathon mean"), "what does hackathon mean")
        XCTAssertNil(QuickFacts.explicitQuery(in: "what's that"), "needs the conversation: the model resolves it")
        XCTAssertNil(QuickFacts.explicitQuery(in: "what's in front of me"))
        XCTAssertNil(QuickFacts.explicitQuery(in: "look around"))
        XCTAssertNil(QuickFacts.explicitQuery(in: "look it up"))
        XCTAssertNil(QuickFacts.explicitQuery(in: "who is here"))
    }

    func testRefusesSavedNamesAndTheWearer() async {
        let source = FakeQuickFactSource()
        source.facts["the Longhorns game"] = QuickFact(text: "Texas 34, Ole Miss 27, final.", source: "sports")
        let facts = QuickFacts(source: source, blockedNames: { ["Marcus Lee", "Caleb"] })
        var r = await facts.answer("look up Marcus")
        XCTAssertEqual(r, .refused)
        r = await facts.answer("who is caleb bae")
        XCTAssertEqual(r, .refused)
        r = await facts.answer("where does Lee work")
        XCTAssertEqual(r, .refused)
        r = await facts.answer("look up the Longhorns game")
        XCTAssertEqual(r, .fact(QuickFact(text: "Texas 34, Ole Miss 27, final.", source: "sports")))
        XCTAssertEqual(source.queries, ["the Longhorns game"], "names never reach the network")
        XCTAssertEqual(QuickFacts.phrase(.refused), "I don't look people up.")
    }

    func testOutcomesWithoutAKeyOrWithoutAnAnswer() async {
        let source = FakeQuickFactSource()
        source.isConfigured = false
        var r = await QuickFacts(source: source).answer("HackTX")
        XCTAssertEqual(r, .unavailable)
        XCTAssertTrue(source.queries.isEmpty)
        source.isConfigured = true
        r = await QuickFacts(source: source).answer("HackTX")
        XCTAssertEqual(r, .nothing)
        source.error = URLError(.timedOut)
        r = await QuickFacts(source: source).answer("HackTX")
        XCTAssertEqual(r, .failed)
        r = await QuickFacts(source: source).answer("?")
        XCTAssertEqual(r, .nothing, "nothing to search")
    }

    func testHTTPErrorsAndPagesFlowThroughTheClient() async throws {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.queue = []; StubURLProtocol.requests = []
        let client = SerpApiClient(apiKey: "test-key", session: URLSession(configuration: c))
        StubURLProtocol.queue = [.init(status: 200, headers: ["Content-Type": "application/json"], body: #"{"answer_box":{"type":"organic_result","snippet":"A hackathon is an event where people build software together over a day or two."}}"#)]
        let fact = try await client.lookup("what is a hackathon")
        XCTAssertEqual(fact?.text, "A hackathon is an event where people build software together over a day or two.")
        let url = try XCTUnwrap(StubURLProtocol.requests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://serpapi.com/search.json?"), url)
        XCTAssertTrue(url.contains("q=what%20is%20a%20hackathon"), url)
        StubURLProtocol.queue = [.init(status: 401, headers: [:], body: #"{"error":"Invalid API key"}"#)]
        do { _ = try await client.lookup("x"); XCTFail("expected an error") } catch { XCTAssertEqual(error as? SerpApiClient.ClientError, .http(401)) }
        let outcome = await QuickFacts(source: client).answer("hackathon")
        XCTAssertEqual(outcome, .failed, "an empty stub queue answers 500")
    }

    func testPhrasesNeverContainTheWakeWord() {
        for o: QuickFacts.Outcome in [.refused, .nothing, .unavailable, .failed] {
            XCTAssertFalse(QuickFacts.phrase(o).localizedCaseInsensitiveContains("poyo"))
            XCTAssertFalse(QuickFacts.phrase(o).localizedCaseInsensitiveContains("familiar"))
        }
    }
}
