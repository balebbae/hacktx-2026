import Foundation
import QuartzCore

// Types added by S3 (Core is frozen). Everything here is consumed by `VoiceSpeaker`, the synthesizers and S5's wiring.

/// 16 kHz mono Float32 audio produced by a synthesizer.
struct SynthesizedAudio: Equatable {
    let samples: [Float]
    let sampleRate: Double
    /// "elevenlabs" | "elevenlabs-cache" | "apple" | "fake"
    let source: String

    var duration: TimeInterval { Double(samples.count) / sampleRate }
}

/// Turns text into 16 kHz PCM. `ElevenLabsTTS`, `AppleTTS` and the test fakes conform.
protocol SpeechSynthesizer: AnyObject {
    var id: String { get }
    func synthesize(_ text: String) async throws -> SynthesizedAudio
}

/// Plays 16 kHz mono Float32 through the one audio engine. `AudioEngineController` conforms; tests use a fake.
protocol PCMPlayback: AnyObject {
    /// Returns the host-clock window of the playback, or nil if it was stopped before any sample played.
    func play(_ audio: SynthesizedAudio, audience: Audience) async -> ClosedRange<TimeInterval>?
    func stop()
}

/// S7: `Utterance` (Core, frozen) carries no volume, so the speaker looks the gain up by category / dedupeKey.
/// "Marcus." for a person who just started talking is whispered at −6 dB; everything else plays at unity.
enum SpeakerVolumeHint {
    static let speakingGainDB: Float = -6

    static func gainDB(for u: Utterance) -> Float {
        if u.category == "speaking" || (u.dedupeKey?.hasPrefix("speaking:") ?? false) { return speakingGainDB }
        return 0
    }

    /// Linear multiplier for the PCM samples.
    static func gain(for u: Utterance) -> Float { powf(10, gainDB(for: u) / 20) }
}

/// Tries `primary` and falls back to `fallback` on any error (including the 1.2 s first-byte timeout).
final class FallbackSynthesizer: SpeechSynthesizer {
    let primary: SpeechSynthesizer
    let fallback: SpeechSynthesizer
    var onFallback: ((String, Error) -> Void)?
    var id: String { "\(primary.id)>\(fallback.id)" }

    init(primary: SpeechSynthesizer, fallback: SpeechSynthesizer) {
        self.primary = primary
        self.fallback = fallback
    }

    func synthesize(_ text: String) async throws -> SynthesizedAudio {
        do { return try await primary.synthesize(text) } catch {
            onFallback?(text, error)
            return try await fallback.synthesize(text)
        }
    }
}

/// Counting semaphore for structured concurrency (ElevenLabs allows us 2 requests in flight).
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { available = count }

    func wait() async {
        if available > 0 { available -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let next = waiters.first { waiters.removeFirst(); next.resume() } else { available += 1 }
    }
}

enum VoiceFactory {
    /// Sarah (premade, American, "mature, reassuring, confident"). Overridden by `ELEVENLABS_VOICE_ID`.
    static let defaultVoiceID = "EXAVITQu4vr4xnSDxMaL"
    static let model = "eleven_flash_v2_5"

    /// ElevenLabs (cached on disk) with Apple fallback when a key is present; Apple only otherwise.
    static func makeSynthesizer(apiKey: String?, voiceID: String? = nil, cacheDirectory: URL? = nil, session: URLSession = .shared) -> SpeechSynthesizer {
        let apple = AppleTTS()
        guard let apiKey, !apiKey.isEmpty else { return apple }
        let cache = cacheDirectory.map(PhraseCache.init(directory:)) ?? PhraseCache()
        let eleven = ElevenLabsTTS(apiKey: apiKey, voiceID: voiceID ?? defaultVoiceID, cache: cache, session: session)
        return FallbackSynthesizer(primary: eleven, fallback: apple)
    }

    /// The production speaker: priority queue over the given synthesizer and playback.
    static func makeSpeaker(apiKey: String? = Secrets.elevenLabsAPIKey, voiceID: String? = Secrets.elevenLabsVoiceID, playback: PCMPlayback, cacheDirectory: URL? = nil, clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) -> VoiceSpeaker {
        VoiceSpeaker(synthesizer: makeSynthesizer(apiKey: apiKey, voiceID: voiceID, cacheDirectory: cacheDirectory), playback: playback, clock: clock)
    }

    static func makeCuePolicy() -> FamiliarCuePolicy { FamiliarCuePolicy() }
}

extension Phrasebook {
    /// Everything the speaker may say for the given names, so a `prewarm` fills the disk cache before the demo.
    static func prewarmSet(names: [String]) -> [String] {
        var out: [String] = []
        for name in names where !name.isEmpty {
            for band in BearingBand.all { for distance in Distance.all { out.append(appeared(name: name, band: band, distance: distance)) } }
            for band in [BearingBand.left, .right, .ahead] { out.append(approaching(name: name, from: band)) }
            out.append(arrived(name: name))
            out.append(left(name: name))
            out.append(speaking(name: name))
            out.append(calling(name: name))
            out.append(texting(name: name))
            out.append(notVisible(name: name))
            out.append(saved(name: name))
        }
        out += fixedPhrases
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Phrases that do not depend on a name.
    static var fixedPhrases: [String] {
        var out: [String] = [nobody]
        for k in 0...4 { out.append(rollCallOthers(count: k)) }
        for k in 1...4 { out.append(rollCallNoKnown(count: k)) }
        for band in [BearingBand.left, .right, .ahead] { out.append(unknownClose(band: band)) }
        out += [wantToRemember, lookTowardMe, wasThatAYes, whatShouldICallYou, nothingSaved, theyLeft]
        out += ChatterMode.allCases.map(mode)
        out += [muted, unmuted, didNotGetThat]
        return out
    }
}
