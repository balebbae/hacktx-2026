import Foundation
import SwiftUI
import QuartzCore

/// Keys for the Settings this session adds. Stored in UserDefaults so S5 can read them when wiring `Services.make`.
enum UserSettings {
    static let voiceProvider = "voiceProvider"              // "elevenlabs" | "apple"
    static let embeddingProvider = "embeddingProvider"      // "ondevice" | "modal"
    static let matchThreshold = "matchThreshold"            // 0.25…0.60
    static let minFacePx = "minFacePx"
    static let audioRoute = "audioRoute"                    // AudioRoute storage
    static let volumePrimary = "volumePrimary"              // "whoIsHere" | "rememberThem"
    static let cueSpeaking = "cueSpeaking"
    static let cueWave = "cueWave"
    static let cueSmile = "cueSmile"
    static let readinessDone = "readinessDone"
    static let autoReplyInSimulator = "autoReplyInSimulator"
    static let selfEnrollUseFixture = "selfEnrollUseFixture"   // S10: enroll_marcus clip instead of the front camera
}

/// UI-side owner of the S4 modules. Until S5 wires `Services.make`, the coordinator hands us the S1 stand-ins
/// (`StubConsentFlow`, `InMemoryPeopleStore`); in that case we build the real consent flow, router and
/// `JSONPeopleStore` on top of the coordinator's perception / transcriber / speaker so the demo runs end-to-end.
/// S5: delete the bridging branch and call `FlowFactory` from `Services.make`; the views only talk to this object.
@MainActor
final class FlowRuntime: ObservableObject {
    @Published private(set) var consentState: ConsentState = .idle
    @Published private(set) var people: [Person] = []
    @Published private(set) var nameGuess: NameGuess?
    @Published private(set) var lastSaved: Person?
    @Published private(set) var isBridged = false
    @Published private(set) var lastCommand: String?

    private(set) var consentFlow: ConsentFlow?
    private(set) var router: CommandRouter?
    private(set) var peopleStore: PeopleStore?
    private(set) var jsonStore: JSONPeopleStore?
    private(set) var nameCache: NameGuestCacheBox?
    private(set) var metaClient: MetaModelClient?
    private(set) var clipRecorder: AudioChunkClipRecorder?
    private(set) var meeting: MeetingContextProvider?
    private(set) var contacts: ContactsBridge?
    private(set) var services: Services?
    let manualCommands = ManualCommandSource()
    private var tasks: [Task<Void, Never>] = []
    private weak var coordinator: AppCoordinator?
    private weak var state: AppState?

    final class NameGuestCacheBox { let cache: NameGuessCache; init(_ c: NameGuessCache) { cache = c } }

    func bind(services s: Services, state: AppState, coordinator: AppCoordinator) {
        guard s !== services else { return }
        tearDown()
        services = s; self.state = state; self.coordinator = coordinator
        let flow: ConsentFlow
        let store: PeopleStore
        if s.consentFlow is StubConsentFlow {
            isBridged = true
            let contacts: ContactsBridge = s.contacts is NoopContactsBridge ? CNContactsBridge(thumbnailData: { [weak self] p in self?.jsonStore?.thumbnailURL(for: p).flatMap { try? Data(contentsOf: $0) } }) : s.contacts
            // The gallery only serves embeddings whose modelID matches, so the store must follow the live embedder
            // (w600k_mbf on the real pipeline, "fake" for ScriptedPerception).
            let json = JSONPeopleStore(paths: .documents, modelID: (s.perception as? PerceptionPipeline)?.embedder.modelID ?? "fake", contacts: contacts)
            jsonStore = json
            self.contacts = contacts
            store = json
            let intel = IntelligenceFactory.make()
            metaClient = intel.metaClient
            let cache = NameGuessCache(extractor: intel.nameExtractor, userName: { [weak state] in state?.userName ?? "" })
            cache.start(transcriber: s.transcriber, perception: s.perception)
            nameCache = NameGuestCacheBox(cache)
            let recorder = AudioChunkClipRecorder()
            recorder.start(audio: s.audioInput)
            clipRecorder = recorder
            let meeting = LocationMeetingContext(placeOverride: { [weak state] in state?.placeName })
            meeting.start()
            self.meeting = meeting
            flow = FlowFactory.makeConsentFlow(perception: s.perception, transcriber: s.transcriber, speaker: s.speaker, cueGate: s.cueGate, peopleStore: json, contacts: contacts, nameExtractor: intel.nameExtractor, yesNo: intel.yesNo, clipRecorder: recorder, meeting: meeting, userName: { [weak state] in state?.userName ?? "Your friend" }, nameGuess: cache)
            tasks.append(Task { [weak self] in
                for await g in cache.$guess.values { self?.nameGuess = g }
            })
            Task { await intel.metaClient?.warmUp() }
        } else {
            isBridged = false
            flow = s.consentFlow
            store = s.peopleStore
            jsonStore = s.peopleStore as? JSONPeopleStore
            self.contacts = s.contacts
        }
        consentFlow = flow
        peopleStore = store
        let r = FlowFactory.makeCommandRouter(perception: s.perception, speaker: s.speaker, cueGate: s.cueGate, consentFlow: flow, peopleStore: store, contacts: s.contacts is NoopContactsBridge ? (jsonStore.map { _ in CNContactsBridge() } ?? s.contacts) : s.contacts, setMode: { [weak state] m in state?.mode = m }, setMuted: { [weak state] m in state?.muted = m })
        r.startObserving()
        r.attach(sources: s.commandSources + [manualCommands])
        router = r
        tasks.append(Task { [weak self] in
            for await st in flow.subscribe() { await MainActor.run { self?.consentState = st; if case let .done(p) = st { self?.lastSaved = p } } }
        })
        tasks.append(Task { [weak self] in
            for await _ in store.changes() { await MainActor.run { self?.people = store.all() } }
        })
        people = store.all()
    }

    func tearDown() {
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        router?.stop(); nameCache?.cache.stop(); clipRecorder?.stop()
        router = nil; consentFlow = nil
    }

    // MARK: Actions used by the views

    func send(_ c: Command) {
        lastCommand = "\(c)"
        coordinator?.log("command \(c)")
        manualCommands.send(c)
    }
    func whoIsHere() { send(.whoIsHere) }
    func rememberThem() { send(.rememberThem) }
    func tapAnswer(yes: Bool) { consentFlow?.tapAnswer(yes: yes) }
    func cancelConsent() { send(.cancel) }

    var showsConsentCard: Bool {
        switch consentState { case .asking, .listening, .saving: return true; default: return false }
    }

    func refreshPeople() { people = peopleStore?.all() ?? [] }
    func remove(_ p: Person) { try? peopleStore?.remove(id: p.id); refreshPeople() }
    func resetPeople() { try? jsonStore?.removeAll(); for p in peopleStore?.all() ?? [] { try? peopleStore?.remove(id: p.id) }; refreshPeople() }
    func update(_ p: Person) { try? peopleStore?.add(p); refreshPeople() }
    func thumbnail(for p: Person) -> UIImage? {
        if let url = jsonStore?.thumbnailURL(for: p) ?? Optional(MemoryPaths.documents.resolve(thumbnailPath: p.thumbnailPath)) { return UIImage(contentsOfFile: url.path) }
        return nil
    }
    func clipURL(for p: Person) -> URL? { jsonStore?.consentClipURL(for: p) ?? p.consent.clipURL }

    /// Demo controls: inject a fake reply as the other person (Simulator only).
    func fakeReply(_ text: String) {
        (services?.transcriber as? FakeTranscriber)?.emit(.init(speaker: .other, text: text))
    }
    var hasFakeTranscriber: Bool { services?.transcriber is FakeTranscriber }
}
