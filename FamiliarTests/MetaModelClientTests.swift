import XCTest
@testable import Familiar

/// Canned HTTP responses; no network.
final class StubURLProtocol: URLProtocol {
    struct Reply { let status: Int; let headers: [String: String]; let body: String }
    nonisolated(unsafe) static var queue: [Reply] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        var req = request
        if let stream = request.httpBodyStream { // body comes as a stream; read it so tests can inspect
            stream.open(); var data = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n <= 0 { break }; data.append(buf, count: n) }
            buf.deallocate(); stream.close(); req.httpBody = data
        }
        Self.requests.append(req)
        let reply = Self.queue.isEmpty ? Reply(status: 500, headers: [:], body: "") : Self.queue.removeFirst()
        Self.lock.unlock()
        let resp = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MetaModelClientTests: XCTestCase {
    private func client() -> MetaModelClient {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.queue = []; StubURLProtocol.requests = []
        return MetaModelClient(apiKey: "test-key", session: URLSession(configuration: c), safetyIdentifier: "abc")
    }
    private func ok(_ content: String, finish: String = "stop") -> StubURLProtocol.Reply {
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
        return .init(status: 200, headers: ["Content-Type": "application/json"], body: #"{"choices":[{"finish_reason":"\#(finish)","message":{"role":"assistant","content":"\#(escaped)"}}]}"#)
    }

    func testNameRequestShapeAndParse() async throws {
        let c = client()
        StubURLProtocol.queue = [ok(#"{"name":"Marcus","confidence":0.95}"#)]
        let g = try await c.introducedName(transcript: MetaModelClient.formatTranscript([seg(.other, "Hey, hi! I'm Marcus.")]))
        XCTAssertEqual(g.name, "Marcus"); XCTAssertEqual(g.confidence, 0.95, accuracy: 0.001); XCTAssertEqual(g.source, "meta")
        let req = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(req.url, MetaModelClient.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "muse-spark-1.3")
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body["prompt_cache_key"] as? String, "familiar-name-v1")
        XCTAssertEqual(body["safety_identifier"] as? String, "abc")
        let rf = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(rf["type"] as? String, "json_schema")
        let js = try XCTUnwrap(rf["json_schema"] as? [String: Any])
        XCTAssertEqual(js["strict"] as? Bool, true)
        XCTAssertEqual(js["name"] as? String, "IntroducedName")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.last?["content"] as? String ?? "").contains("OTHER: Hey, hi! I'm Marcus."))
        XCTAssertNil(body["image"], "text only ever leaves the phone")
    }

    func testNonStopFinishIsRejected() async {
        let c = client()
        StubURLProtocol.queue = [ok(#"{"answer":"yes"}"#, finish: "length")]
        do { _ = try await c.yesNo(reply: "yes"); XCTFail("should throw") } catch {}
    }

    func testRetriesOnceOn429HonouringRetryAfter() async throws {
        let c = client()
        StubURLProtocol.queue = [.init(status: 429, headers: ["Retry-After": "0"], body: ""), ok(#"{"answer":"no"}"#)]
        let t0 = Date()
        let a = try await c.yesNo(reply: "nah")
        XCTAssertEqual(a, .no)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3)
    }

    func testGivesUpAfterSecond503() async {
        let c = client()
        StubURLProtocol.queue = [.init(status: 503, headers: ["Retry-After": "0"], body: ""), .init(status: 503, headers: ["Retry-After": "0"], body: "")]
        do { _ = try await c.yesNo(reply: "yes"); XCTFail("should throw") } catch {}
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testIntent() async throws {
        let c = client()
        StubURLProtocol.queue = [ok(#"{"intent":"call","name":"Marcus"}"#)]
        let i = try await c.intent(sentence: "call marcus")
        XCTAssertEqual(i, .init(intent: "call", name: "Marcus"))
    }

    func testExtractorsDegradeGracefullyWithoutKey() async {
        let c = MetaModelClient(apiKey: nil)
        XCTAssertFalse(c.isConfigured)
        let g = await MetaNameExtractor(client: c).otherPersonName(segments: [seg(.other, "I'm Marcus")], userName: "Priya")
        XCTAssertNil(g.name)
        let yn = await MetaYesNoClassifier(client: c).classify("yes")
        XCTAssertEqual(yn, .unclear)
    }
}
