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
    /// Deep link waiting for the UI (`familiar://introduce` from an NFC tag opens the self-enroll flow). HomeView clears it.
    @Published var pendingRoute: AppRoute?

    private var tasks: [Task<Void, Never>] = []
    private weak var state: AppState?
    private var frameTimes: [TimeInterval] = []

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
        do {
            try await s.frameSource.start()
            try await s.perception.start(frames: s.frameSource, gallery: s.peopleStore)
            try await s.transcriber.start(audio: s.audioInput)
        } catch {
            lastError = error.localizedDescription
            log("start failed: \(error.localizedDescription)")
        }
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
            for await seg in s.transcriber.subscribe() { await MainActor.run { self?.transcript = Array((self?.transcript ?? []).suffix(39)) + [seg] } }
        })
        tasks.append(Task { [weak self] in
            for await st in s.consentFlow.subscribe() { await MainActor.run { self?.consentState = st; self?.log("consent → \(st)") } }
        })
        log("started source \(source.title)")
    }

    func shutdown() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        services?.perception.stop()
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

    private func noteFrame(at t: TimeInterval) {
        frameTimes.append(t)
        frameTimes.removeAll { $0 < t - 2 }
        if frameTimes.count > 1 { fps = Double(frameTimes.count - 1) / max(0.001, frameTimes.last! - frameTimes.first!) }
    }

    func log(_ text: String) {
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
        let text = RollCallSkeleton.phrase(tracks: s.perception.currentTracks())
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

/// Minimal roll call for the skeleton; S3 ships the real `RollCall` in Flows/RollCall.swift.
enum RollCallSkeleton {
    static func phrase(tracks: [TrackSnapshot]) -> String {
        let known = tracks.filter { $0.identity.isKnown }.sorted { $0.bearing.degrees < $1.bearing.degrees }
        let others = tracks.count - known.count
        if tracks.isEmpty { return Phrasebook.nobody }
        if known.isEmpty { return Phrasebook.rollCallNoKnown(count: others) }
        let parts = known.map { Phrasebook.rollCallKnown(name: $0.identity.name ?? "", band: $0.bearing.band, distance: $0.distance) }
        return (parts + [Phrasebook.rollCallOthers(count: others)]).joined(separator: " ")
    }
}
