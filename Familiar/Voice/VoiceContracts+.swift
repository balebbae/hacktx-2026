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

/// Tries `primary` and falls back to `fallback` on any error (including the 3 s first-byte timeout).
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

/// The wearer's speech preferences from You → Accessibility, read by key so the Voice module does not depend on the
/// UI (`YouSettings.speechRate` / `speechVolume` write them). A missing key means "unchanged": fresh installs and
/// the test host hear the voice exactly as before. Read at use, so a slider moves the next cue.
enum SpeechPreferences {
    static let rateKey = "speechRate"
    static let volumeKey = "speechVolume"
    /// The Voice and cues toggle for "Marcus." when a known person starts talking. Default on, as the policy always was.
    static let speakingCueKey = "cueSpeaking"

    /// 0.8…1.3, default 1: multiplies the voice's natural pace.
    static func rateMultiplier(_ defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: rateKey) as? Double else { return 1 }
        return min(1.3, max(0.8, value))
    }

    /// 0.3…1, default 1: a linear gain applied to every utterance, inside the phone volume.
    static func volume(_ defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: volumeKey) as? Double else { return 1 }
        return min(1, max(0.3, value))
    }

    static func speakingCueEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: speakingCueKey) as? Bool ?? true
    }
}

enum VoiceFactory {
    /// Sarah (premade, American, "mature, reassuring, confident"). Overridden by `ELEVENLABS_VOICE_ID`.
    static let defaultVoiceID = "EXAVITQu4vr4xnSDxMaL"
    /// Same model as the dashboard agent, so Poyo sounds like the voice picked there. `ELEVENLABS_MODEL_ID`
    /// overrides it (`eleven_flash_v2_5` is about 0.5 s faster to first byte but sounds flatter).
    static var model: String { Secrets.elevenLabsModelID ?? "eleven_v4_turbo" }

    /// ElevenLabs (cached on disk) with Apple fallback when a key is present; Apple only otherwise. Both follow the
    /// wearer's speech rate (`SpeechPreferences`); volume is applied once, in the speaker.
    static func makeSynthesizer(apiKey: String?, voiceID: String? = nil, cacheDirectory: URL? = nil, session: URLSession = .shared) -> SpeechSynthesizer {
        let apple = AppleTTS()
        apple.rateMultiplier = { SpeechPreferences.rateMultiplier() }
        guard let apiKey, !apiKey.isEmpty else { return apple }
        let cache = cacheDirectory.map(PhraseCache.init(directory:)) ?? PhraseCache()
        let eleven = ElevenLabsTTS(apiKey: apiKey, voiceID: voiceID ?? defaultVoiceID, cache: cache, session: session)
        eleven.speedProvider = { SpeechPreferences.rateMultiplier() }
        let synth = FallbackSynthesizer(primary: eleven, fallback: apple)
        synth.onFallback = { text, error in DiagnosticLog.write("TTS fell back to the Apple voice (\(error)): \(text)") }
        return synth
    }

    /// The production speaker: priority queue over the given synthesizer and playback.
    static func makeSpeaker(apiKey: String? = Secrets.elevenLabsAPIKey, voiceID: String? = Secrets.elevenLabsVoiceID, playback: PCMPlayback, cacheDirectory: URL? = nil, clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) -> VoiceSpeaker {
        let speaker = VoiceSpeaker(synthesizer: makeSynthesizer(apiKey: apiKey, voiceID: voiceID, cacheDirectory: cacheDirectory), playback: playback, clock: clock)
        speaker.volumeProvider = { Float(SpeechPreferences.volume()) }
        return speaker
    }

    /// The production policy honours the "Speaking first" toggle; `FamiliarCuePolicy()` alone (tests) keeps it on.
    static func makeCuePolicy() -> FamiliarCuePolicy {
        FamiliarCuePolicy(speakingCueEnabled: { SpeechPreferences.speakingCueEnabled() })
    }
}

extension Phrasebook {
    /// Everything the speaker may say for the given names, so a `prewarm` fills the disk cache before the demo.
    static func prewarmSet(names: [String]) -> [String] {
        var out: [String] = []
        for name in names where !name.isEmpty {
            for hour in [11, 12, 1] {
                for distance in Distance.all { out.append(appeared(name: name, bearing: .atClock(hour), distance: distance)) }
                out.append(approaching(name: name, from: .atClock(hour)))
            }
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
        for hour in [11, 12, 1] { out.append(unknownClose(bearing: .atClock(hour))) }
        out += [shouldIAdd, scanningFace, lookTowardMe, wasThatAYes, whatShouldICallYou, nothingSaved, theyLeft]
        out += ChatterMode.allCases.map(mode)
        out += [muted, unmuted, didNotGetThat]
        out += alertPhrases
        return out
    }

    /// The vision alerts most likely indoors, so they play without a TTS round trip (prewarmed at every start).
    static var alertPhrases: [String] {
        var out: [String] = []
        for thing in ["wall", "door", "glass door", "chair", "table", "couch", "counter", "desk", "obstacle", "pillar", "stairs"] {
            for m in [nil, 1.0, 2, 3, 4] as [Double?] { out.append(pathAlert(what: thing, bearing: .atClock(12), meters: m)) }
            for hour in [11, 1] { out.append(pathAlert(what: thing, bearing: .atClock(hour), meters: 1)) }
        }
        return out
    }
}

extension Utterance {
    /// Played the moment a "Poyo, …" request is heard; interrupts whatever is playing.
    static let heardYou = Utterance(text: "", priority: 0, category: "chime", personID: nil, dedupeKey: nil, audience: .user, earcon: true)
}
