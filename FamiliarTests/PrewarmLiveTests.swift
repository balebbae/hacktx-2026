import XCTest
@testable import Familiar

/// Opt-in: fills the ElevenLabs disk cache with the demo vocabulary using a real key.
/// Run with `TEST_RUNNER_ELEVENLABS_API_KEY=… TEST_RUNNER_PREWARM_DIR=/abs/path xcodebuild … -only-testing:FamiliarTests/PrewarmLiveTests test`.
final class PrewarmLiveTests: XCTestCase {
    func testPrewarmDemoVocabulary() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["ELEVENLABS_API_KEY"], !key.isEmpty else { throw XCTSkip("ELEVENLABS_API_KEY not set; live prewarm skipped") }
        let dir = env["PREWARM_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("tts-prewarm")
        let cache = PhraseCache(directory: dir)
        let tts = ElevenLabsTTS(apiKey: key, voiceID: env["ELEVENLABS_VOICE_ID"] ?? VoiceFactory.defaultVoiceID, cache: cache)
        tts.firstByteTimeout = 10
        let names = (env["PREWARM_NAMES"] ?? "Marcus").split(separator: ",").map(String.init)
        let phrases = Phrasebook.prewarmSet(names: names)
        let speaker = VoiceSpeaker(synthesizer: tts, playback: FakePlayback())
        let started = CACurrentMediaTime()
        await speaker.prewarm(phrases)
        let missing = phrases.filter { !tts.isCached($0) }
        print("[PrewarmLiveTests] \(phrases.count - missing.count)/\(phrases.count) phrases cached in \(String(format: "%.1f", CACurrentMediaTime() - started)) s at \(dir.path)")
        for m in missing { print("[PrewarmLiveTests] MISSING: \(m)") }
        XCTAssertTrue(missing.isEmpty, "uncached: \(missing)")
    }
}
