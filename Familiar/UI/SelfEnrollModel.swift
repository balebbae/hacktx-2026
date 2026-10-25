import Foundation
import CoreGraphics
import QuartzCore
import SwiftUI

/// Deep-link routes the app understands (`familiar://introduce` from a link, QR code or the demo controls).
enum AppRoute: Equatable {
    case introduce

    /// `familiar://introduce` (host) and `familiar:///introduce` (path) both count; nothing else does.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "familiar" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host == "introduce" || (host.isEmpty && path == "introduce") { self = .introduce } else { return nil }
    }
}

/// S10: the other person holds the phone and enrolls themselves. Separate from the view so the whole flow is testable
/// against `FakePerception` / `JSONPeopleStore` in a temp folder. Nothing is written before `answer(yes: true)`.
@MainActor
final class SelfEnrollModel: ObservableObject, Identifiable {
    enum Step: Equatable {
        case intro, scanning, name, consent, saving, done(Person), cancelled

        static func == (a: Step, b: Step) -> Bool {
            switch (a, b) {
            case (.intro, .intro), (.scanning, .scanning), (.name, .name), (.consent, .consent), (.saving, .saving), (.cancelled, .cancelled): return true
            case let (.done(x), .done(y)): return x.id == y.id
            default: return false
            }
        }
    }

    struct Config: Equatable {
        /// Auto-advance once this many good embeddings exist.
        var targetEmbeddings = 8
        /// "Next" unlocks here (fixtures and the fake pipeline deliver fewer than 8).
        var minEmbeddings = 5
        var minQuality: Float = 0.3
        var pollInterval: TimeInterval = 0.1
        var burstSeconds: Double = 3
        static let `default` = Config()
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var collected = 0
    @Published private(set) var preview: CGImage?
    @Published private(set) var hint = Phrasebook.lookAtCamera
    @Published private(set) var error: String?
    @Published var name = ""
    @Published var phone = ""

    let config: Config
    let userName: String
    /// Mirror the preview like a selfie camera (front camera only).
    let mirrorsPreview: Bool

    private let perception: Perception
    private let frames: FrameSource
    private let store: PeopleStore
    private let contacts: ContactsBridge
    private let speaker: Speaker
    private let cueGate: CueGate?
    private let meeting: MeetingContextProvider
    private let onBegin: () async -> Void
    private let onEnd: () async -> Void
    private var scanTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private(set) var gathered: [FaceEmbedding] = []
    private(set) var track: Int?
    private var lastBurstAt: TimeInterval = -.infinity
    private var opened = false
    private var cameraRunning = false
    private var closed = false

    init(perception: Perception, frames: FrameSource, store: PeopleStore, contacts: ContactsBridge, speaker: Speaker, cueGate: CueGate?, meeting: MeetingContextProvider, userName: String, mirrorsPreview: Bool = false, config: Config = .default, onBegin: @escaping () async -> Void = {}, onEnd: @escaping () async -> Void = {}) {
        self.perception = perception; self.frames = frames; self.store = store; self.contacts = contacts; self.speaker = speaker
        self.cueGate = cueGate; self.meeting = meeting; self.userName = userName; self.mirrorsPreview = mirrorsPreview
        self.config = config; self.onBegin = onBegin; self.onEnd = onEnd
    }

    // MARK: Texts (all from the Phrasebook; no name is spoken before YES)

    var introText: String { Phrasebook.selfEnrollIntro(userName: userName) }
    var consentText: String { Phrasebook.selfEnrollConsent(name: cleanName) }
    var doneText: String { Phrasebook.selfEnrollHandBack(name: cleanName) }
    var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanPhone: String? { let t = phone.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
    var canContinueScan: Bool { collected >= config.minEmbeddings }
    var canSubmitName: Bool { !cleanName.isEmpty }
    var progress: Double { min(1, Double(collected) / Double(max(1, config.targetEmbeddings))) }

    // MARK: Flow

    /// The stranger opened the sheet: tell the wearer and hold the cues. Call once.
    func open() {
        guard !opened else { return }
        opened = true
        cueGate?.consentActive = true
        Task { await speaker.speak(Utterance(text: Phrasebook.someoneIntroducing, priority: 0, category: "selfEnroll", personID: nil, dedupeKey: nil, audience: .user, earcon: true)) }
    }

    /// Intro → scanning: front camera (or fixture) through the real pipeline, collecting the best embeddings of the largest face.
    func beginScan() async {
        open()
        guard step == .intro else { return }
        step = .scanning
        collected = 0; gathered = []; track = nil; error = nil
        hint = Phrasebook.noFaceYet
        await onBegin()
        do {
            try await frames.start()
            try await perception.start(frames: frames, gallery: store)
            cameraRunning = true
        } catch {
            self.error = error.localizedDescription
        }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            for await event in perception.subscribe() {
                if Task.isCancelled { return }
                if case let .snapshot(_, image) = event, let image { await MainActor.run { self.preview = image } }
            }
        }
        scanTask?.cancel()
        scanTask = Task { [weak self] in await self?.scanLoop() }
    }

    private func scanLoop() async {
        while !Task.isCancelled, step == .scanning {
            poll()
            if collected >= config.targetEmbeddings { finishScan(); return }
            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        }
    }

    /// One scan tick: largest facing face wins, bursts are re-requested while it is on screen.
    func poll() {
        let tracks = perception.currentTracks()
        let facing = tracks.filter(\.isFacingUser)
        guard let target = (facing.isEmpty ? tracks : facing).max(by: { $0.faceHeightPx < $1.faceHeightPx }) else {
            hint = Phrasebook.noFaceYet
            return
        }
        let now = CACurrentMediaTime()
        if target.trackID != track || now - lastBurstAt > config.burstSeconds - 0.5 {
            track = target.trackID
            perception.requestBurst(track: target.trackID, seconds: config.burstSeconds)
            lastBurstAt = now
        }
        let best = perception.bestEmbeddings(track: target.trackID, max: config.targetEmbeddings).filter { $0.quality >= config.minQuality }
        if best.count >= gathered.count { gathered = best }
        collected = gathered.count
        hint = Phrasebook.scanProgress(collected, of: config.targetEmbeddings)
    }

    /// Scanning → name entry. Only when at least `minEmbeddings` good embeddings exist.
    func finishScan() {
        guard step == .scanning, canContinueScan else { return }
        scanTask?.cancel(); scanTask = nil
        stopCamera()
        step = .name
    }

    func submitName() {
        guard step == .name, canSubmitName else { return }
        step = .consent
    }

    func backToName() { if step == .consent { step = .name } }

    /// The consent tap. NO cancels and saves nothing; YES is the only path that writes anything.
    func answer(yes: Bool) async {
        guard step == .consent else { return }
        guard yes else { await cancel(); return }
        step = .saving
        let id = UUID()
        var thumbnailPath = ""
        if let jpeg = gathered.first(where: { $0.thumbnailJPEG != nil })?.thumbnailJPEG, let json = store as? JSONPeopleStore {
            thumbnailPath = (try? json.writeThumbnail(jpeg, for: id)) ?? ""
        }
        let record = ConsentRecord(kind: .tap, at: Date(), askedText: consentText, replyTranscript: "(tapped YES on the phone, self-enrolled)", clipURL: nil)
        var person = Person(id: id, name: cleanName, phone: cleanPhone, embeddings: gathered, thumbnailPath: thumbnailPath, consent: record, met: meeting.current(), contactIdentifier: nil)
        if let track { perception.assignIdentity(track: track, personID: id, name: person.name) }
        do { try store.add(person) } catch {
            self.error = "Save failed: \(error.localizedDescription)"
            step = .consent
            return
        }
        if let identifier = try? await contacts.create(for: person) {
            person.contactIdentifier = identifier
            try? store.add(person)
        }
        await end()
        await speaker.speak(Utterance(text: Phrasebook.saved(name: person.name), priority: 0, category: "selfEnroll", personID: id, dedupeKey: nil, audience: .user, earcon: false))
        step = .done(person)
    }

    /// Any step: stop everything, keep nothing, tell the wearer.
    func cancel() async {
        switch step { case .done, .cancelled: return; default: break }
        step = .cancelled
        gathered = []; collected = 0
        await end()
        if opened {
            await speaker.speak(Utterance(text: Phrasebook.nothingSaved, priority: 0, category: "selfEnroll", personID: nil, dedupeKey: nil, audience: .user, earcon: false))
        }
    }

    /// Done screen dismissed: release the cue gate and the camera if still held.
    func close() async { await end() }

    private func stopCamera() {
        guard cameraRunning else { return }
        cameraRunning = false
        perception.stop()
        frames.stop()
        previewTask?.cancel(); previewTask = nil
    }

    private func end() async {
        scanTask?.cancel(); scanTask = nil
        stopCamera()
        cueGate?.consentActive = false
        guard !closed else { return }
        closed = true
        await onEnd()
    }
}
