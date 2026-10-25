import XCTest
@testable import Familiar

final class ElevenLabsTTSTests: XCTestCase {
    var dir: URL!
    var cache: PhraseCache!

    override func setUp() {
        StubURLProtocol.reset()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("eleven-tests-\(UUID().uuidString)")
        cache = PhraseCache(directory: dir)
    }

    override func tearDown() { StubURLProtocol.reset(); try? FileManager.default.removeItem(at: dir) }

    func makeTTS() -> ElevenLabsTTS {
        ElevenLabsTTS(apiKey: "test-key", voiceID: "VOICE", cache: cache, session: StubURLProtocol.makeSession())
    }

    func testRequestShapeDecodeAndCache() async throws {
        let pcm = PCM16.encode([Float](repeating: 0.25, count: 1_600))
        StubURLProtocol.handler = { _ in (200, pcm) }
        let tts = makeTTS()
        let audio = try await tts.synthesize("Marcus, ahead, close.")
        XCTAssertEqual(audio.samples.count, 1_600)
        XCTAssertEqual(audio.sampleRate, 16_000)
        XCTAssertEqual(audio.source, "elevenlabs")
        XCTAssertEqual(audio.samples[10], 0.25, accuracy: 0.001)

        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.elevenlabs.io/v1/text-to-speech/VOICE?output_format=pcm_16000")
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        XCTAssertEqual(body["text"] as? String, "Marcus, ahead, close.")
        XCTAssertEqual(body["model_id"] as? String, "eleven_flash_v2_5")
        XCTAssertNotNil(body["voice_settings"])
        XCTAssertNotNil(body["previous_text"])

        XCTAssertTrue(tts.isCached("Marcus, ahead, close."))
        XCTAssertEqual(cache.files().count, 1)
        let again = try await tts.synthesize("Marcus, ahead, close.")
        XCTAssertEqual(again.samples.count, 1_600)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "second call served from disk")
    }

    func testHTTPErrorSurfaces() async {
        StubURLProtocol.handler = { _ in (401, Data("nope".utf8)) }
        do {
            _ = try await makeTTS().synthesize("x")
            XCTFail("expected failure")
        } catch let e as ElevenLabsTTS.Failure {
            XCTAssertEqual(e, .httpStatus(401))
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(cache.files().count, 0)
    }

    func testFirstByteTimeoutFallsBackToApple() async throws {
        StubURLProtocol.handler = { _ in (200, PCM16.encode([0.1, 0.2])) }
        StubURLProtocol.delay = 1.0
        let tts = makeTTS()
        tts.firstByteTimeout = 0.1
        let apple = FakeSynth(id: "apple")
        let fb = FallbackSynthesizer(primary: tts, fallback: apple)
        var fell: [Error] = []
        fb.onFallback = { _, e in fell.append(e) }
        let started = CACurrentMediaTime()
        let audio = try await fb.synthesize("Marcus left.")
        XCTAssertEqual(audio.source, "apple")
        XCTAssertLessThan(CACurrentMediaTime() - started, 0.8)
        XCTAssertEqual(fell.first as? ElevenLabsTTS.Failure, .timeout)
    }

    func testWarmSkipsCachedPhrases() async throws {
        StubURLProtocol.handler = { _ in (200, PCM16.encode([Float](repeating: 0.1, count: 160))) }
        let tts = makeTTS()
        try await tts.warm("Muted.")
        try await tts.warm("Muted.")
        try await tts.warm("Unmuted.")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(cache.files().count, 2)
    }

    func testFactoryWithoutKeyIsAppleOnly() {
        let synth = VoiceFactory.makeSynthesizer(apiKey: nil, cacheDirectory: dir)
        XCTAssertEqual(synth.id, "apple")
        let withKey = VoiceFactory.makeSynthesizer(apiKey: "k", cacheDirectory: dir)
        XCTAssertEqual(withKey.id, "elevenlabs>apple")
        XCTAssertEqual(VoiceFactory.defaultVoiceID, "EXAVITQu4vr4xnSDxMaL")
    }
}
