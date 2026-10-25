import XCTest
@testable import Familiar

final class ElevenLabsTTSTests: XCTestCase {
    var dir: URL!
    var cache: PhraseCache!

    override func setUp() {
        TTSStubURLProtocol.reset()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("eleven-tests-\(UUID().uuidString)")
        cache = PhraseCache(directory: dir)
    }

    override func tearDown() { TTSStubURLProtocol.reset(); try? FileManager.default.removeItem(at: dir) }

    func makeTTS() -> ElevenLabsTTS {
        ElevenLabsTTS(apiKey: "test-key", voiceID: "VOICE", cache: cache, session: TTSStubURLProtocol.makeSession())
    }

    func testRequestShapeDecodeAndCache() async throws {
        let pcm = PCM16.encode([Float](repeating: 0.25, count: 1_600))
        TTSStubURLProtocol.handler = { _ in (200, pcm) }
        let tts = makeTTS()
        let audio = try await tts.synthesize("Marcus, ahead, close.")
        XCTAssertEqual(audio.samples.count, 1_600)
        XCTAssertEqual(audio.sampleRate, 16_000)
        XCTAssertEqual(audio.source, "elevenlabs")
        XCTAssertEqual(audio.samples[10], 0.25, accuracy: 0.001)

        let sent = try XCTUnwrap(TTSStubURLProtocol.requests.first)
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
        XCTAssertEqual(TTSStubURLProtocol.requests.count, 1, "second call served from disk")
    }

    func testHTTPErrorSurfaces() async {
        TTSStubURLProtocol.handler = { _ in (401, Data("nope".utf8)) }
        do {
            _ = try await makeTTS().synthesize("x")
            XCTFail("expected failure")
        } catch let e as ElevenLabsTTS.Failure {
            XCTAssertEqual(e, .httpStatus(401))
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(cache.files().count, 0)
    }

    func testFirstByteTimeoutFallsBackToApple() async throws {
        TTSStubURLProtocol.handler = { _ in (200, PCM16.encode([0.1, 0.2])) }
        TTSStubURLProtocol.delay = 1.0
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
        TTSStubURLProtocol.handler = { _ in (200, PCM16.encode([Float](repeating: 0.1, count: 160))) }
        let tts = makeTTS()
        try await tts.warm("Muted.")
        try await tts.warm("Muted.")
        try await tts.warm("Unmuted.")
        XCTAssertEqual(TTSStubURLProtocol.requests.count, 2)
        XCTAssertEqual(cache.files().count, 2)
    }

    func testSpeedGoesIntoVoiceSettingsAndItsOwnCacheEntry() async throws {
        TTSStubURLProtocol.handler = { _ in (200, PCM16.encode([Float](repeating: 0.1, count: 160))) }
        let tts = makeTTS()
        _ = try await tts.synthesize("Marcus left.")
        tts.speedProvider = { 1.3 }   // the slider's maximum; ElevenLabs accepts at most 1.2
        XCTAssertEqual(tts.speed, 1.2, accuracy: 1e-9)
        XCTAssertFalse(tts.isCached("Marcus left."), "another speed is another entry")
        _ = try await tts.synthesize("Marcus left.")
        XCTAssertEqual(TTSStubURLProtocol.requests.count, 2)
        let sent = try XCTUnwrap(TTSStubURLProtocol.requests.last)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])
        XCTAssertEqual(settings["speed"] as? Double ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(cache.files().count, 2)
        XCTAssertEqual(ElevenLabsTTS.cacheModel("m", speed: 1), "m", "1.0 keeps the prewarmed keys valid")
        XCTAssertEqual(ElevenLabsTTS.cacheModel("m", speed: 0.85), "m@0.85")
    }

    func testSpeechPreferencesDefaultToUnchanged() {
        let defaults = UserDefaults(suiteName: "ElevenLabsTTSTests.speech")!
        defaults.removePersistentDomain(forName: "ElevenLabsTTSTests.speech")
        XCTAssertEqual(SpeechPreferences.rateMultiplier(defaults), 1)
        XCTAssertEqual(SpeechPreferences.volume(defaults), 1)
        defaults.set(2.0, forKey: SpeechPreferences.rateKey)
        defaults.set(0.1, forKey: SpeechPreferences.volumeKey)
        XCTAssertEqual(SpeechPreferences.rateMultiplier(defaults), 1.3, "clamped to the slider's range")
        XCTAssertEqual(SpeechPreferences.volume(defaults), 0.3)
    }

    func testFactoryWithoutKeyIsAppleOnly() {
        let synth = VoiceFactory.makeSynthesizer(apiKey: nil, cacheDirectory: dir)
        XCTAssertEqual(synth.id, "apple")
        let withKey = VoiceFactory.makeSynthesizer(apiKey: "k", cacheDirectory: dir)
        XCTAssertEqual(withKey.id, "elevenlabs>apple")
        XCTAssertEqual(VoiceFactory.defaultVoiceID, "EXAVITQu4vr4xnSDxMaL")
    }
}
