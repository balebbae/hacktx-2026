import Foundation
import QuartzCore

/// Routes every `Command` (wake word, buttons, gestures) and the goodbye signal to the right module.
@MainActor
final class CommandRouter: ObservableObject {
    private let perception: Perception
    private let speaker: Speaker
    private let cueGate: CueGate
    private let consentFlow: ConsentFlow
    private let peopleStore: PeopleStore
    private let contacts: ContactsBridge
    private let setMode: (ChatterMode) -> Void
    private let setMuted: (Bool) -> Void
    private let rollCall: ([TrackSnapshot]) -> String
    private let clock: () -> TimeInterval
    private var tasks: [Task<Void, Never>] = []
    private var lastGoodbyeFlowAt: TimeInterval = -.infinity
    private var consentActive = false

    @Published private(set) var lastUtterance: Utterance?
    @Published private(set) var lastSeen: [UUID: LastSeen] = [:]
    @Published private(set) var handled: [Command] = []
    var goodbyeCooldown: TimeInterval = 60

    init(perception: Perception, speaker: Speaker, cueGate: CueGate, consentFlow: ConsentFlow, peopleStore: PeopleStore, contacts: ContactsBridge, setMode: @escaping (ChatterMode) -> Void, setMuted: @escaping (Bool) -> Void, rollCall: @escaping ([TrackSnapshot]) -> String = RollCallSkeleton.phrase, clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.perception = perception; self.speaker = speaker; self.cueGate = cueGate; self.consentFlow = consentFlow
        self.peopleStore = peopleStore; self.contacts = contacts; self.setMode = setMode; self.setMuted = setMuted
        self.rollCall = rollCall; self.clock = clock
    }

    func attach(sources: [CommandSource]) {
        for source in sources {
            tasks.append(Task { [weak self] in
                for await c in source.subscribe() { await self?.handle(c) }
            })
        }
    }

    /// S3's `GoodbyeDetector` publishes host-clock timestamps; the router only needs the stream.
    func attachGoodbyes(_ stream: AsyncStream<TimeInterval>) {
        tasks.append(Task { [weak self] in
            for await t in stream { await self?.goodbyeDetected(at: t) }
        })
    }

    /// Keeps the last-seen memory and the consent-active flag current.
    func startObserving() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await e in self.perception.subscribe() { self.note(e) }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await st in self.consentFlow.subscribe() {
                switch st { case .idle, .done, .declined, .cancelled: self.consentActive = false; default: self.consentActive = true }
            }
        })
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks.removeAll() }

    private func note(_ e: PerceptionEvent) {
        let now = clock()
        switch e {
        case let .snapshot(tracks, _):
            for t in tracks { if case let .known(pid, name, _) = t.identity { lastSeen[pid] = LastSeen(name: name, personID: pid, bearing: t.bearing, at: now) } }
        case let .knownLeft(pid, name, last): lastSeen[pid] = LastSeen(name: name, personID: pid, bearing: last, at: now)
        default: break
        }
    }

    // MARK: Commands

    func handle(_ c: Command) async {
        handled.append(c)
        switch c {
        case .whoIsHere:
            await say(rollCall(perception.currentTracks()), priority: 1, category: "rollcall", dedupe: "rollcall", earcon: true)
        case .rememberThem:
            guard !consentActive else { return }
            Task { await consentFlow.begin(confirmFirst: false) }
        case let .setMode(m):
            setMode(m)
            await say(Phrasebook.mode(m), priority: 0, category: "mode")
        case .mute:
            cueGate.muted = true; setMuted(true)
            await say(Phrasebook.muted, priority: 0, category: "mode")
        case .unmute:
            cueGate.muted = false; setMuted(false)
            await say(Phrasebook.unmuted, priority: 0, category: "mode")
        case let .call(name):
            if let p = peopleStore.find(name: name) { await say(Phrasebook.calling(name: p.name), priority: 0, category: "command"); contacts.call(p) }
            else { await say(Phrasebook.unknownPerson(name), priority: 0, category: "command") }
        case let .text(name):
            if let p = peopleStore.find(name: name) { await say(Phrasebook.texting(name: p.name), priority: 0, category: "command"); contacts.text(p) }
            else { await say(Phrasebook.unknownPerson(name), priority: 0, category: "command") }
        case let .whereIs(name):
            await whereIs(name)
        case .cancel:
            consentFlow.cancel()
            speaker.stopAll()
        case .repeatLast:
            if let u = lastUtterance { await speaker.speak(u) } else { await say(Phrasebook.didNotGetThat, priority: 1, category: "command") }
        }
    }

    /// Person-detail buttons: open the dialer / Messages for a specific person without a spoken prefix lookup.
    func callDirect(_ p: Person) { contacts.call(p) }
    func textDirect(_ p: Person) { contacts.text(p) }

    private func whereIs(_ name: String) async {
        let needle = name.lowercased()
        let tracks = perception.currentTracks()
        if let t = tracks.first(where: { ($0.identity.name ?? "").lowercased().hasPrefix(needle) }), let n = t.identity.name {
            await say(Phrasebook.rollCallKnown(name: n, band: t.bearing.band, distance: t.distance), priority: 1, category: "whereis"); return
        }
        if let seen = lastSeen.values.filter({ $0.name.lowercased().hasPrefix(needle) }).max(by: { $0.at < $1.at }) {
            await say(Phrasebook.lastSeen(name: seen.name, band: seen.bearing.band), priority: 1, category: "whereis"); return
        }
        if let p = peopleStore.find(name: name) { await say(Phrasebook.notVisible(name: p.name), priority: 1, category: "whereis"); return }
        await say(Phrasebook.unknownPerson(name), priority: 1, category: "whereis")
    }

    /// Goodbye → offer to remember, only if a stranger is close, no flow is active and the cooldown passed.
    func goodbyeDetected(at t: TimeInterval) async {
        guard !consentActive, t - lastGoodbyeFlowAt >= goodbyeCooldown else { return }
        let strangerClose = perception.currentTracks().contains { !$0.identity.isKnown && $0.distance == .close }
        guard strangerClose else { return }
        lastGoodbyeFlowAt = t
        Task { await consentFlow.begin(confirmFirst: true) }
    }

    private func say(_ text: String, priority: Int, category: String, dedupe: String? = nil, earcon: Bool = false) async {
        let u = Utterance(text: text, priority: priority, category: category, personID: nil, dedupeKey: dedupe, audience: .user, earcon: earcon)
        lastUtterance = u
        guard cueGate.admit(u) else { return }
        await speaker.speak(u)
    }
}
