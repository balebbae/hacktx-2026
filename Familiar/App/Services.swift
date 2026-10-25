import Foundation
import SwiftUI
import QuartzCore
import os

/// Dependency container. `make(source:)` wires whatever implementations exist; today (S1) that is the fakes
/// plus a pass-through `CuePolicy`. S5 replaces the fakes with the real modules.
@MainActor
final class Services: ObservableObject {
    enum Source: Equatable, Hashable {
        case phone
        case glasses
        case fixture(String)

        var storageKey: String {
            switch self { case .phone: return "phone"; case .glasses: return "glasses"; case let .fixture(n): return "fixture:\(n)" }
        }
        init?(storageKey: String?) {
            guard let storageKey else { return nil }
            if storageKey == "phone" { self = .phone } else if storageKey == "glasses" { self = .glasses } else if storageKey.hasPrefix("fixture:") { self = .fixture(String(storageKey.dropFirst(8))) } else { return nil }
        }
        var title: String {
            switch self { case .phone: return "Phone camera"; case .glasses: return "Glasses"; case let .fixture(n): return "Fixture: \(n)" }
        }
        static var defaultForThisDevice: Source {
            #if targetEnvironment(simulator)
            return .fixture("mixed")
            #else
            return .phone
            #endif
        }
    }

    let source: Source
    let frameSource: FrameSource
    let perception: Perception
    let audioInput: AudioInput
    let transcriber: Transcriber
    let speaker: Speaker
    let cuePolicy: CuePolicy
    let cueGate: CueGate
    let peopleStore: PeopleStore
    let contacts: ContactsBridge
    let nameExtractor: NameExtractor
    let yesNo: YesNoClassifier
    let consentFlow: ConsentFlow
    let commandSources: [CommandSource]
    /// What the transcriber hears: the mic with the app's own speech blanked out, so it never answers itself.
    lazy var transcriberAudio: AudioInput = audioInput
    /// Wearer/other loudness split; Settings calibrates it to the wearer's voice.
    var vad: LoudnessSplit?
    /// On-device scene and hazard awareness over the same frames.
    let scene = SceneAwareness()
    /// The always-on eye: redacted frames → vision model → what matters for walking.
    let cloudScene = CloudScene(client: VisionLLMClient())

    /// Convenience accessors for the skeleton UI (nil when the real module is wired instead).
    var logSpeaker: LogSpeaker? { speaker as? LogSpeaker }
    var scripted: ScriptedPerception? { perception as? ScriptedPerception }

    init(source: Source, frameSource: FrameSource, perception: Perception, audioInput: AudioInput, transcriber: Transcriber, speaker: Speaker, cuePolicy: CuePolicy, cueGate: CueGate, peopleStore: PeopleStore, contacts: ContactsBridge, nameExtractor: NameExtractor, yesNo: YesNoClassifier, consentFlow: ConsentFlow, commandSources: [CommandSource]) {
        self.source = source; self.frameSource = frameSource; self.perception = perception; self.audioInput = audioInput; self.transcriber = transcriber; self.speaker = speaker; self.cuePolicy = cuePolicy; self.cueGate = cueGate; self.peopleStore = peopleStore; self.contacts = contacts; self.nameExtractor = nameExtractor; self.yesNo = yesNo; self.consentFlow = consentFlow; self.commandSources = commandSources
    }

    private static var sharedEngine: AudioEngineController?

    /// Real perception (S2), audio/voice/speech (S3) and glasses (S6). The consent flow, router and JSON people store
    /// are built by `FlowRuntime` (S4) on top of these, which is why `consentFlow`/`peopleStore` stay as stand-ins here.
    static func make(source: Source, state: AppState) -> Services {
        let defaults = UserDefaults.standard
        let frameSource: FrameSource
        switch source {
        case .phone:
            frameSource = PhoneCameraFrameSource()
        case .glasses:
            frameSource = GlassesFactory.makeFrameSource()
        case let .fixture(name):
            frameSource = VideoFileFrameSource(fixtureNamed: name) ?? SilentFrameSource()
        }

        let useScripted = defaults.bool(forKey: "useScriptedPerception")
        let threshold = defaults.object(forKey: UserSettings.matchThreshold) as? Float ?? 0.40
        let embedder = PerceptionFactory.defaultEmbedder()
        let perception: Perception = useScripted ? ScriptedPerception() : PerceptionFactory.make(embedder: embedder, threshold: threshold)
        // The store perception matches against must be the one consent saves into, filtered to this embedder's
        // model id; FlowRuntime picks this same instance up.
        let peopleStore = JSONPeopleStore(paths: .documents, modelID: useScripted ? "fake" : embedder.modelID, contacts: CNContactsBridge())

        // One engine for the life of the app: it owns the AVAudioSession, and re-applying the session on every
        // source switch re-routes Bluetooth audio on the glasses.
        let route = AudioRoute(storageKey: defaults.string(forKey: UserSettings.audioRoute)) ?? .phoneMicGlassesA2DP
        let engine: AudioEngineController
        if let shared = sharedEngine {
            engine = shared
            if shared.route != route { do { try shared.setRoute(route) } catch { NSLog("[Services] audio route switch failed: %@", "\(error)") } }
        } else {
            engine = AudioFactory.makeEngine(route: route)
            sharedEngine = engine
        }
        do { try engine.start() } catch { NSLog("[Services] audio engine start failed: %@", "\(error)") }
        if let glasses = frameSource as? GlassesStreamCoordinator {
            Task.detached { [weak engine] in for await active in glasses.streamingChanges() { engine?.glassesStreamActive = active } }
        }

        let speaker: Speaker
        if defaults.string(forKey: UserSettings.voiceProvider) == "log" {
            speaker = LogSpeaker(speakAloud: state.speakLogSpeakerAloud)
        } else {
            let useEleven = defaults.string(forKey: UserSettings.voiceProvider) != "apple"
            speaker = VoiceFactory.makeSpeaker(apiKey: useEleven ? Secrets.elevenLabsAPIKey : nil, playback: engine)
        }

        let vad = AudioFactory.makeVoiceActivity(audio: engine.rawInput)
        if let rms = defaults.object(forKey: UserSettings.userVoiceRMS) as? Float { vad.userRMS = rms }
        // MARK: S7 — who is talking to me. VAD `.other` speech + mouth-openness variance of known, facing tracks
        // → `speakingStarted` once per track-session. Lives on the real pipeline only (ScriptedPerception scripts it).
        if let pipeline = perception as? PerceptionPipeline {
            let activeSpeaker = ActiveSpeaker()
            activeSpeaker.attach(vad)
            pipeline.activeSpeaker = activeSpeaker
        }
        // MARK: end S7
        let transcriber: Transcriber
        #if targetEnvironment(simulator)
        transcriber = FakeTranscriber(transcriptNamed: "conversation") ?? FakeTranscriber(text: "")
        #else
        transcriber = SpeechFactory.makeTranscriber(speakerGuess: { vad.guess(at: $0) }, speechDetected: { vad.noteExternalSpeech($0, at: $1) })
        #endif
        let commands: [CommandSource] = [SpeechFactory.makeCommandSource(transcriber: transcriber)]

        let services = Services(source: source, frameSource: frameSource, perception: perception, audioInput: engine.rawInput, transcriber: transcriber, speaker: speaker, cuePolicy: VoiceFactory.makeCuePolicy(), cueGate: CueGate(), peopleStore: peopleStore, contacts: NoopContactsBridge(), nameExtractor: NoopNameExtractor(), yesNo: RulesYesNo(), consentFlow: StubConsentFlow(), commandSources: commands)
        services.transcriberAudio = engine.transcriberInput
        services.vad = vad
        return services
    }
}

extension AudioRoute {
    init?(storageKey: String?) {
        switch storageKey {
        case "phoneMicGlassesA2DP": self = .phoneMicGlassesA2DP
        case "glassesHFP": self = .glassesHFP
        case "glassesStreamMic": self = .glassesStreamMic
        case "phoneOnly": self = .phoneOnly
        default: return nil
        }
    }
}

// MARK: - Skeleton stand-ins (replaced by the real modules in S3/S4/S5)

/// Every known event becomes exactly one utterance via `Phrasebook`. Unknown-count changes are silent.
struct PassThroughCuePolicy: CuePolicy {
    func utterances(for e: PerceptionEvent, mode: ChatterMode, now: TimeInterval) -> [Utterance] {
        func u(_ text: String, _ pid: UUID?, _ category: String, priority: Int = 1) -> Utterance {
            Utterance(text: text, priority: priority, category: category, personID: pid, dedupeKey: "\(category):\(pid?.uuidString ?? "")", audience: .user, earcon: true)
        }
        switch e {
        case let .knownAppeared(t): if case let .known(pid, name, _) = t.identity { return [u(Phrasebook.appeared(name: name, bearing: t.bearing, distance: t.distance), pid, "appeared")] }
        case let .knownApproaching(t): if case let .known(pid, name, _) = t.identity { return [u(Phrasebook.approaching(name: name, from: t.bearing), pid, "approaching")] }
        case let .knownArrived(t): if case let .known(pid, name, _) = t.identity { return [u(Phrasebook.arrived(name: name), pid, "arrived")] }
        case let .knownLeft(pid, name, _): return [u(Phrasebook.left(name: name), pid, "left", priority: 2)]
        case let .speakingStarted(t): if mode != .quiet, case let .known(pid, name, _) = t.identity { return [u(Phrasebook.speaking(name: name), pid, "speaking")] }
        default: break
        }
        return []
    }
}

final class SilentFrameSource: FrameSource {
    private let bus = EventBus<Frame>(defaultPolicy: .bufferingNewest(1))
    func subscribe() -> AsyncStream<Frame> { bus.subscribe() }
    func start() async throws {}
    func stop() {}
}

final class SilentAudioInput: AudioInput {
    private let bus = EventBus<AudioChunk>(defaultPolicy: .bufferingNewest(64))
    func subscribe() -> AsyncStream<AudioChunk> { bus.subscribe() }
    var route: AudioRoute { .phoneOnly }
    var micLevel: Float { 0 }
}

@MainActor
final class InMemoryPeopleStore: PeopleStore {
    private var people: [Person] = []
    private let bus = EventBus<Void>()
    private let galleryLock = OSAllocatedUnfairLock(initialState: Gallery(modelID: "fake", people: []))
    var modelID = "fake"

    nonisolated func gallery() -> Gallery { galleryLock.withLock { $0 } }
    func all() -> [Person] { people }
    func add(_ p: Person) throws { people.removeAll { $0.id == p.id }; people.append(p); rebuild() }
    func remove(id: UUID) throws { people.removeAll { $0.id == id }; rebuild() }
    func find(name: String) -> Person? { people.first { $0.name.lowercased().hasPrefix(name.lowercased()) } }
    func changes() -> AsyncStream<Void> { bus.subscribe() }
    private func rebuild() {
        let g = Gallery(modelID: modelID, people: people.map { ($0.id, $0.name, $0.embeddings.filter { $0.modelID == modelID }.map(\.vector)) })
        galleryLock.withLock { $0 = g }
        bus.publish(())
    }
}

struct NoopContactsBridge: ContactsBridge {
    func create(for p: Person) async throws -> String { "noop-\(p.id.uuidString)" }
    func delete(identifier: String) async throws {}
    func call(_ p: Person) {}
    func text(_ p: Person) {}
}

struct NoopNameExtractor: NameExtractor {
    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess { NameGuess(name: nil, confidence: 0, source: "none") }
}

struct RulesYesNo: YesNoClassifier {
    func classify(_ reply: String) async -> YesNo {
        let r = reply.lowercased()
        if ["yes", "yeah", "yep", "yup", "sure", "okay", "ok", "of course", "go ahead", "fine", "absolutely"].contains(where: { r.contains($0) }) { return .yes }
        if ["no", "nope", "nah", "rather not", "don't"].contains(where: { r.contains($0) }) { return .no }
        return .unclear
    }
}

final class StubConsentFlow: ConsentFlow {
    private let bus = EventBus<ConsentState>()
    func subscribe() -> AsyncStream<ConsentState> { bus.subscribe() }
    func begin(confirmFirst: Bool) async { bus.publish(.cancelled(reason: "Consent flow not wired yet (S4).")) ; bus.publish(.idle) }
    func tapAnswer(yes: Bool) {}
    func cancel() { bus.publish(.idle) }
}
