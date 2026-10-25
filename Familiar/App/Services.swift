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

    /// Convenience accessors for the skeleton UI (nil when the real module is wired instead).
    var logSpeaker: LogSpeaker? { speaker as? LogSpeaker }
    var scripted: ScriptedPerception? { perception as? ScriptedPerception }

    init(source: Source, frameSource: FrameSource, perception: Perception, audioInput: AudioInput, transcriber: Transcriber, speaker: Speaker, cuePolicy: CuePolicy, cueGate: CueGate, peopleStore: PeopleStore, contacts: ContactsBridge, nameExtractor: NameExtractor, yesNo: YesNoClassifier, consentFlow: ConsentFlow, commandSources: [CommandSource]) {
        self.source = source; self.frameSource = frameSource; self.perception = perception; self.audioInput = audioInput; self.transcriber = transcriber; self.speaker = speaker; self.cuePolicy = cuePolicy; self.cueGate = cueGate; self.peopleStore = peopleStore; self.contacts = contacts; self.nameExtractor = nameExtractor; self.yesNo = yesNo; self.consentFlow = consentFlow; self.commandSources = commandSources
    }

    static func make(source: Source, state: AppState) -> Services {
        let frameSource: FrameSource
        switch source {
        case .phone, .glasses:
            frameSource = PhoneCameraFrameSource()
        case let .fixture(name):
            frameSource = VideoFileFrameSource(fixtureNamed: name) ?? SilentFrameSource()
        }
        let perception = ScriptedPerception()
        let speaker = LogSpeaker(speakAloud: state.speakLogSpeakerAloud)
        let transcriber = FakeTranscriber(transcriptNamed: "conversation") ?? FakeTranscriber(text: "")
        let store = InMemoryPeopleStore()
        return Services(source: source, frameSource: frameSource, perception: perception, audioInput: SilentAudioInput(), transcriber: transcriber, speaker: speaker, cuePolicy: PassThroughCuePolicy(), cueGate: CueGate(), peopleStore: store, contacts: NoopContactsBridge(), nameExtractor: NoopNameExtractor(), yesNo: RulesYesNo(), consentFlow: StubConsentFlow(), commandSources: [])
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
        case let .knownAppeared(t): if case let .known(pid, name, _) = t.identity { return [u(Phrasebook.appeared(name: name, band: t.bearing.band, distance: t.distance), pid, "appeared")] }
        case let .knownApproaching(t): if case let .known(pid, name, _) = t.identity { return [u(Phrasebook.approaching(name: name, from: t.bearing.band), pid, "approaching")] }
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
