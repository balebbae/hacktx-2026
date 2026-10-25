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
        sceneReading = nil
        s.cloudScene.trackedFaces = { [weak perception = s.perception] in perception?.currentTracks().map(\.faceBox) ?? [] }
        s.cloudScene.start(frames: s.frameSource)
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
            for await event in s.perception.subscribe() { await self?.handle(event: event, services: s, state: state) }
        })
        if let logSpeaker = s.logSpeaker {
            tasks.append(Task { [weak self] in
                for await entry in logSpeaker.subscribe() { await MainActor.run { self?.utterances = Array((self?.utterances ?? []).suffix(49)) + [entry] } }
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
        for u in s.cuePolicy.utterances(for: event, mode: state.mode, now: now) where s.cueGate.admit(u) {
            Task { await s.speaker.speak(u) }
        }
    }

    /// Hazards are spoken at once (priority 0, even when muted); a new place only in chatty mode.
    private func handle(scene e: SceneEvent, services s: Services, state: AppState) {
        log("scene \(e)")
        let u: Utterance
        switch e {
        case let .hazard(kind):
            u = Utterance(text: Phrasebook.hazard(kind), priority: 0, category: "hazard", personID: nil, dedupeKey: "hazard:\(kind.rawValue)", audience: .user, earcon: true)
        case let .placeChanged(place):
            guard state.mode == .chatty else { return }
            u = Utterance(text: Phrasebook.place(place), priority: 3, category: "place", personID: nil, dedupeKey: "place", audience: .user, earcon: false)
        }
        guard s.cueGate.admit(u) else { return }
        Task { await s.speaker.speak(u) }
    }

    /// Path and hazard alerts from the vision reading at once; a one-line gist when the scene changed.
    private func handle(reading r: SceneReading, services s: Services, state: AppState) {
        sceneReading = r
        log("vision \(r.path.rawValue)\(r.pathMeters.map { " \($0) m" } ?? ""): \(r.summary)")
        let inConversation = s.transcriber.recentSegments(seconds: 15).contains { $0.isFinal && $0.speaker == .other }
        for u in narration.utterances(for: r, mode: state.mode, now: CACurrentMediaTime(), inConversation: inConversation) where s.cueGate.admit(u) {
            Task { await s.speaker.speak(u) }
        }
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
        let u = Utterance(text: text, priority: 1, category: "rollcall", personID: nil, dedupeKey: "rollcall", audience: .user, earcon: true)
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
