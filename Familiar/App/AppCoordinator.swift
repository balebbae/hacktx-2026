import Foundation
import SwiftUI
import QuartzCore

/// Owns the live `Services`, runs the perception → cue policy → gate → speaker loop, and keeps the judge-view feeds
/// (latest snapshot, utterance log, event log, transcript). S5 extends this with audio lifecycle and the command router.
@MainActor
final class AppCoordinator: ObservableObject {
    struct LoggedEvent: Identifiable, Equatable { let id = UUID(); let at: TimeInterval; let text: String }

    @Published private(set) var services: Services?
    @Published private(set) var isReady = false
    @Published private(set) var tracks: [TrackSnapshot] = []
    @Published private(set) var preview: CGImage?
    @Published private(set) var utterances: [LogSpeaker.Entry] = []
    @Published private(set) var events: [LoggedEvent] = []
    @Published private(set) var transcript: [TranscriptSegment] = []
    @Published private(set) var consentState: ConsentState = .idle
    @Published private(set) var fps: Double = 0
    @Published private(set) var lastError: String?
    /// Latest vision reading (judge view).
    @Published private(set) var sceneReading: SceneReading?
    /// Deep link waiting for the UI (`familiar://introduce` from an NFC tag opens the self-enroll flow). HomeView clears it.
    @Published var pendingRoute: AppRoute?

    private var tasks: [Task<Void, Never>] = []
    private weak var state: AppState?
    private var frameTimes: [TimeInterval] = []
    private var narration = NarrationPolicy()
    /// One hazard is one hazard, whichever detector saw it first.
    private var hazards = HazardRegistry()
    private var lastCaptionAt: TimeInterval = -.infinity
    /// A routine caption waiting for a pause in the dialogue; in a busy room the pause comes a few seconds later.
    private var pendingCaption: (u: Utterance, at: TimeInterval)?
    private let captionPatience: TimeInterval = 10

    /// True when the app is only the XCTest host: the live pipeline stays off so background tasks never interfere with tests.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil

    func boot(state: AppState) async {
        guard self.state == nil else { return }
        self.state = state
        isReady = true
        if Self.isRunningTests { log("test host: pipeline not started"); return }
        await restart(source: state.source)
    }

    func restart(source: Services.Source) async {
        guard let state else { return }
        shutdown()
        let s = Services.make(source: source, state: state)
        services = s
        tracks = []; preview = nil; events = []; utterances = []; transcript = []
        s.cueGate.muted = state.muted
        lastError = nil
        // The camera starts on its own: glasses that are not linked yet must not keep speech and perception down.
        if let glasses = s.frameSource as? GlassesFrameSource {
            tasks.append(Task { [weak self] in
                for await st in glasses.statusChanges() { self?.glassesStatusChanged(st) }
            })
            ensureGlasses()
        } else {
            do { try await s.frameSource.start() } catch { report("camera start failed", error) }
        }
        do { try await s.perception.start(frames: s.frameSource, gallery: s.peopleStore) } catch { report("perception start failed", error) }
        do { try await s.transcriber.start(audio: s.transcriberAudio) } catch { report("speech start failed", error) }
        // Routine cues (priority ≥ 1) wait while the wearer is talking; the gate had this flag but nothing set it.
        if let vad = s.vad {
            tasks.append(Task { for await v in vad.subscribe() { s.cueGate.userSpeaking = v.isSpeech && v.guess == .user } })
        }
        s.scene.start(frames: s.frameSource)
        narration = NarrationPolicy()
        hazards = HazardRegistry()
        lastCaptionAt = -.infinity
        pendingCaption = nil
        sceneReading = nil
        s.cloudScene.trackedFaces = { [weak perception = s.perception] in perception?.currentTracks().map(\.faceBox) ?? [] }
        s.scene.faces = { [weak perception = s.perception] in perception?.currentTracks() ?? [] }
        s.scene.speechActive = { [weak transcriber = s.transcriber] in !(transcriber?.recentSegments(seconds: 5).isEmpty ?? true) }
        s.motion.start()
        s.scene.onExpansion = { [weak motion = s.motion] rate, t in motion?.noteExpansion(rate, at: t) }
        s.cloudScene.isMoving = { [weak motion = s.motion] in motion?.isMoving() ?? false }
        s.cloudScene.start(frames: s.frameSource)
        // Alerts must play the moment they are decided, and the first "Marcus, coming toward you." must not switch
        // to the Apple voice: fill the TTS cache for the alerts, then for everyone in the store (kept on disk).
        let names = s.peopleStore.all().map(\.name)
        tasks.append(Task.detached(priority: .background) { await s.speaker.prewarm(Phrasebook.demoVocabulary(names: names)) })
        // Every line that reaches the wearer's ear is a turn Poyo took, whichever lane wrote it: the model and
        // "say that again" read them back from `dialogue`.
        if let voice = s.speaker as? VoiceSpeaker {
            voice.onSpoken = { spoken in
                DiagnosticLog.write("said[p\(spoken.utterance.priority) \(spoken.utterance.category)\(spoken.source == "apple" ? " apple" : "")] \(spoken.utterance.text)")
                if spoken.utterance.audience == .user { s.dialogue.record(.poyo, spoken.utterance.text, at: spoken.window?.lowerBound ?? CACurrentMediaTime()) }
            }
            voice.onDropped = { u, why in DiagnosticLog.write("dropped[\(u.category)] \(why): \(u.text)") }
        }
        tasks.append(Task { [weak self] in
            for await r in s.cloudScene.subscribe() { await self?.handle(reading: r, services: s, state: state) }
        })
        tasks.append(Task { [weak self] in
            for await e in s.scene.subscribe() { self?.handle(scene: e, services: s, state: state) }
        })
        tasks.append(Task { [weak self] in
            for await frame in s.frameSource.subscribe() { await self?.noteFrame(at: frame.timestamp) }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.flushPendingCaption(services: s)
            }
        })
        tasks.append(Task { [weak self] in
            for await event in s.perception.subscribe() { await self?.handle(event: event, services: s, state: state) }
        })
        if let logSpeaker = s.logSpeaker {
            tasks.append(Task { [weak self] in
                for await entry in logSpeaker.subscribe() {
                    if entry.utterance.audience == .user { s.dialogue.record(.poyo, entry.utterance.text, at: entry.at) }
                    await MainActor.run { self?.utterances = Array((self?.utterances ?? []).suffix(49)) + [entry] }
                }
            })
        }
        tasks.append(Task { [weak self] in
            for await seg in s.transcriber.subscribe() {
                if seg.isFinal { DiagnosticLog.heard(seg) }
                await MainActor.run { self?.transcript = Array((self?.transcript ?? []).suffix(39)) + [seg] }
            }
        })
        tasks.append(Task { [weak self] in
            for await st in s.consentFlow.subscribe() { await MainActor.run { self?.consentState = st; self?.log("consent → \(st)") } }
        })
        log("started source \(source.title)")
    }

    private func report(_ what: String, _ error: Error) {
        lastError = error.localizedDescription
        log("\(what): \(error.localizedDescription)")
    }

    // MARK: Glasses keeper
    // DAT sessions end for good on fold, Bluetooth drops or a trip to the Meta AI app, and the SDK never restarts them.
    // While the source is the glasses we keep trying, except when the user has to act (register, allow the camera).

    private var glassesRetry: Task<Void, Never>?
    private var lastGlassesAttempt: TimeInterval = -.infinity

    /// Starts the glasses stream unless it is running, paused by the device, or already being retried.
    func ensureGlasses() {
        guard glassesRetry == nil, let glasses = services?.frameSource as? GlassesFrameSource, !glasses.status.isActive else { return }
        glassesRetry = Task { [weak self] in
            var delay: TimeInterval = 0
            while let self, !Task.isCancelled, self.services?.frameSource === glasses, !glasses.status.isActive {
                let wait = max(delay, self.lastGlassesAttempt + 2 - CACurrentMediaTime())
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, self.services?.frameSource === glasses else { break }
                self.lastGlassesAttempt = CACurrentMediaTime()
                do {
                    try await glasses.start()
                    self.lastError = nil
                    self.log("glasses session started")
                    break
                } catch let e as GlassesError where e == .notRegistered || e == .cameraPermissionDenied {
                    self.report("glasses need you", e)
                    break
                } catch {
                    self.report("glasses retry", error)
                    delay = min(5, max(1, delay * 2))
                }
            }
            // A cancelled loop was replaced by `shutdown()`; leave the new one alone.
            if !Task.isCancelled { self?.glassesRetry = nil }
        }
    }

    private func glassesStatusChanged(_ status: GlassesStatus) {
        switch status {
        case let .stopped(reason) where reason != GlassesFrameSource.userStopReason:
            log("glasses stopped: \(reason)")
            ensureGlasses()
        case let .failed(reason):
            log("glasses failed: \(reason)")
            ensureGlasses()
        case .streaming:
            lastError = nil
        default:
            break
        }
    }

    /// Coming back from the Meta AI app (registration, camera permission) or from the lock screen.
    func appBecameActive() {
        lastGlassesAttempt = -.infinity
        ensureGlasses()
    }

    func shutdown() {
        glassesRetry?.cancel()
        glassesRetry = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        services?.perception.stop()
        services?.scene.stop()
        services?.cloudScene.stop()
        services?.motion.stop()
        services?.frameSource.stop()
        services?.transcriber.stop()
        services?.speaker.stopAll()
    }

    private func handle(event: PerceptionEvent, services s: Services, state: AppState) async {
        switch event {
        case let .snapshot(tracks, preview):
            self.tracks = tracks
            if let preview { self.preview = preview }
            return
        default:
            log(describe(event))
        }
        let now = CACurrentMediaTime()
        // Face to face with someone: only a friend arriving is worth a word; approach / left / speaking cues wait.
        let talking = conversationActive(s)
        for u in s.cuePolicy.utterances(for: event, mode: state.mode, now: now) where s.cueGate.admit(u) {
            if talking, u.priority >= 1, !["appeared", "arrived"].contains(u.category) { continue }
            if u.category == "left", let pid = u.personID {
                // Tracks flicker in a crowd: say "Marcus left." only if he is still gone a few seconds later.
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard s.perception.currentTracks().allSatisfy({ $0.identity.personID != pid }), !(self?.conversationActive(s) ?? true) else { return }
                    await s.speaker.speak(u)
                }
                continue
            }
            Task { await s.speaker.speak(u) }
        }
    }

    /// Hazards are spoken at once (priority 0, even when muted); a new place only in chatty mode; action captions per
    /// `ActionCaption.utterance`.
    private func handle(scene e: SceneEvent, services s: Services, state: AppState) {
        log("scene \(e)")
        let u: Utterance
        switch e {
        case let .hazard(kind):
            guard s.motion.isMoving() else { return }        // standing still: not about to walk into it
            // The vision model may have said "Stairs down, 12 o'clock, 3 meters." a second ago: same stairs.
            guard hazards.admit(HazardSighting(kind: kind.rawValue, clock: 12, meters: nil), now: CACurrentMediaTime()) else { log("hazard \(kind.rawValue) already announced"); return }
            u = Utterance(text: Phrasebook.hazard(kind), priority: 0, category: "hazard", personID: nil, dedupeKey: "hazard:\(kind.rawValue)", audience: .user, earcon: true)
        case let .placeChanged(place):
            guard state.mode == .chatty, !conversationActive(s) else { return }
            u = Utterance(text: Phrasebook.place(place), priority: 3, category: "place", personID: nil, dedupeKey: "place", audience: .user, earcon: false)
        case let .action(c):
            let now = CACurrentMediaTime()
            guard let a = ActionCaption.utterance(for: c, mode: state.mode, moving: s.motion.isMoving(), inConversation: conversationActive(s),
                                                  inDialogueGap: true, sinceLast: now - lastCaptionAt) else { return }
            lastCaptionAt = now
            // Routine captions fit between lines of dialogue, like a film's audio description: held for the next pause.
            if a.priority >= 2, !inDialogueGap(s) { pendingCaption = (a, now); return }
            u = a
        }
        guard s.cueGate.admit(u) else { return }
        Task { await s.speaker.speak(u) }
    }

    /// Nothing heard in the last second.
    private func inDialogueGap(_ s: Services) -> Bool { s.transcriber.recentSegments(seconds: 1).isEmpty }

    private func flushPendingCaption(services s: Services) {
        guard let p = pendingCaption else { return }
        if CACurrentMediaTime() - p.at > captionPatience { pendingCaption = nil; log("caption expired: \(p.u.text)"); return }
        guard inDialogueGap(s), !s.speaker.isSpeaking else { return }
        pendingCaption = nil
        guard s.cueGate.admit(p.u) else { return }
        Task { await s.speaker.speak(p.u) }
    }

    /// Path and hazard alerts from the vision reading at once; a one-line gist when the scene changed. An alert
    /// about a hazard the on-device detector already announced is dropped.
    private func handle(reading r: SceneReading, services s: Services, state: AppState) {
        sceneReading = r
        log("vision \(r.path.rawValue)\(r.pathMeters.map { " \($0) m" } ?? ""): \(r.summary)")
        let now = CACurrentMediaTime()
        for n in narration.decide(for: r, mode: state.mode, now: now, inConversation: conversationActive(s), moving: s.motion.isMoving()) where s.cueGate.admit(n.utterance) {
            if let h = n.hazard, !hazards.admit(h, now: now) { log("hazard \(h.kind) already announced: \(n.utterance.text)"); continue }
            Task { await s.speaker.speak(n.utterance) }
        }
    }

    /// Face to face with someone: speech in the last 12 s while a person is near (close or medium) and facing the
    /// wearer. Speech alone is not enough: in a packed room someone is always talking. The voice split cannot tell
    /// the wearer from others, so it is not used.
    func conversationActive(_ s: Services) -> Bool {
        guard s.perception.currentTracks().contains(where: { $0.distance != .far && $0.isFacingUser }) else { return false }
        return s.transcriber.recentSegments(seconds: 12).contains { $0.isFinal && $0.text.split(separator: " ").count >= 2 }
    }

    private func noteFrame(at t: TimeInterval) {
        frameTimes.append(t)
        frameTimes.removeAll { $0 < t - 2 }
        if frameTimes.count > 1 { fps = Double(frameTimes.count - 1) / max(0.001, frameTimes.last! - frameTimes.first!) }
    }

    func log(_ text: String) {
        DiagnosticLog.write(text)
        events = Array(events.suffix(199)) + [LoggedEvent(at: CACurrentMediaTime(), text: text)]
    }

    private func describe(_ e: PerceptionEvent) -> String {
        switch e {
        case let .unknownCountChanged(n): return "unknownCountChanged \(n)"
        case let .knownLeft(_, name, last): return "knownLeft \(name) (\(last.band.words))"
        case let .cue(_, name, kind): return "cue \(name) \(kind)"
        default:
            if let name = e.personName { return "\(e.kindName) \(name)" }
            return e.kindName
        }
    }

    // MARK: - User actions (routed to the command router in S4/S5)

    func whoIsHere() {
        guard let s = services else { return }
        let text = RollCall.phrase(tracks: s.perception.currentTracks())
        let u = Utterance(text: text, priority: 1, category: "rollcall", personID: nil, dedupeKey: "rollcall", audience: .user, earcon: false)
        log("command whoIsHere")
        Task { await s.speaker.speak(u) }
    }

    func rememberThem() {
        guard let s = services else { return }
        log("command rememberThem")
        Task { await s.consentFlow.begin(confirmFirst: false) }
    }

    func setMuted(_ muted: Bool) {
        services?.cueGate.muted = muted
        if let s = services {
            Task { await s.speaker.speak(Utterance(text: muted ? Phrasebook.muted : Phrasebook.unmuted, priority: 0, category: "mode", personID: nil, dedupeKey: nil, audience: .user, earcon: false)) }
        }
    }

    func setMode(_ mode: ChatterMode) {
        guard let s = services else { return }
        Task { await s.speaker.speak(Utterance(text: Phrasebook.mode(mode), priority: 0, category: "mode", personID: nil, dedupeKey: nil, audience: .user, earcon: false)) }
    }

    func handle(url: URL) {
        log("open url \(url.absoluteString)")
        if let route = AppRoute(url: url) { pendingRoute = route }
    }
}
