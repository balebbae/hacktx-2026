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
    /// What's around: hazards, then the given people line, then place and objects (`SceneAwareness.describe`).
    var surroundings: (String?) -> String = { $0 ?? Phrasebook.nothingToName }
    /// Set when Poyo runs on the vision model: "what's around me" is answered from the live view instead.
    var askAssistant: ((String) async -> Void)?
    /// Everything spoken lately, whichever lane said it: "say that again" repeats Poyo's last line from here.
    var dialogue: DialogueMemory?
    private let clock: () -> TimeInterval
    private var tasks: [Task<Void, Never>] = []
    private var lastGoodbyeFlowAt: TimeInterval = -.infinity
    private var consentActive = false

    @Published private(set) var lastUtterance: Utterance?
    @Published private(set) var lastSeen: [UUID: LastSeen] = [:]
    @Published private(set) var handled: [Command] = []
    var goodbyeCooldown: TimeInterval = 60
    var conversationCooldown: TimeInterval = 180
    private var lastConversationOfferAt: TimeInterval = -.infinity
    /// How long someone new must have been near and facing the wearer before a conversation counts as one with them
    /// (in a packed room there is always talk and always a face somewhere).
    var faceToFaceSeconds: TimeInterval = 20
    /// Faces drop out when a person looks down or away and come back under a new track id (the device logs never
    /// held one id for 20 s), so presence is one stretch across ids that tolerates gaps this long.
    var nearGap: TimeInterval = 5
    private var strangerNear: (first: TimeInterval, last: TimeInterval)?
    private var offeredTracks: Set<Int> = []
    /// One face vector per person already offered, so a new track id of the same person is not asked again.
    private var offeredFaces: [[Float]] = []
    var sameFaceCosine: Float = 0.4

    init(perception: Perception, speaker: Speaker, cueGate: CueGate, consentFlow: ConsentFlow, peopleStore: PeopleStore, contacts: ContactsBridge, setMode: @escaping (ChatterMode) -> Void, setMuted: @escaping (Bool) -> Void, rollCall: @escaping ([TrackSnapshot]) -> String = RollCall.phrase(tracks:), clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.perception = perception; self.speaker = speaker; self.cueGate = cueGate; self.consentFlow = consentFlow
        self.peopleStore = peopleStore; self.contacts = contacts; self.setMode = setMode; self.setMuted = setMuted
        self.rollCall = rollCall; self.clock = clock
    }

    func attach(sources: [CommandSource]) {
        for source in sources {
            let stream = source.subscribe()
            tasks.append(Task { [weak self] in
                for await c in stream { await self?.handle(c) }
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
        let events = perception.subscribe()
        let states = consentFlow.subscribe()
        tasks.append(Task { [weak self] in
            for await e in events { self?.note(e) }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await st in states {
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
            if tracks.contains(where: { !$0.identity.isKnown && $0.distance != .far && $0.isFacingUser }) {
                let first = strangerNear.flatMap { now - $0.last <= nearGap ? $0.first : nil } ?? now
                strangerNear = (first, now)
            } else if let n = strangerNear, now - n.last > nearGap {
                strangerNear = nil                                          // a glance away is fine; walking off is not
            }
        case let .knownLeft(pid, name, last): lastSeen[pid] = LastSeen(name: name, personID: pid, bearing: last, at: now)
        default: break
        }
    }

    // MARK: Commands

    func handle(_ c: Command) async {
        handled.append(c)
        switch c {
        case .whoIsHere:
            await say(rollCall(perception.currentTracks()), priority: 0, category: "rollcall", dedupe: "rollcall")
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
        case .describeSurroundings:
            if let ask = askAssistant { await ask("What's around me?"); return }
            let tracks = perception.currentTracks()
            await say(surroundings(tracks.isEmpty ? nil : rollCall(tracks)), priority: 0, category: "surroundings")
        case .repeatLast:
            if let text = dialogue?.lastPoyoLine(now: clock()) { await say(text, priority: 0, category: "repeat") }
            else if let u = lastUtterance { await speaker.speak(u) }
            else { await say(Phrasebook.didNotGetThat, priority: 1, category: "command") }
        }
    }

    /// Person-detail buttons: open the dialer / Messages for a specific person without a spoken prefix lookup.
    func callDirect(_ p: Person) { contacts.call(p) }
    func textDirect(_ p: Person) { contacts.text(p) }

    private func whereIs(_ name: String) async {
        let needle = name.lowercased()
        let tracks = perception.currentTracks()
        if let t = tracks.first(where: { ($0.identity.name ?? "").lowercased().hasPrefix(needle) }), let n = t.identity.name {
            await say(Phrasebook.rollCallKnown(name: n, bearing: t.bearing, distance: t.distance), priority: 0, category: "whereis"); return
        }
        if let seen = lastSeen.values.filter({ $0.name.lowercased().hasPrefix(needle) }).max(by: { $0.at < $1.at }) {
            await say(Phrasebook.lastSeen(name: seen.name, bearing: seen.bearing), priority: 0, category: "whereis"); return
        }
        if let p = peopleStore.find(name: name) { await say(Phrasebook.notVisible(name: p.name), priority: 0, category: "whereis"); return }
        await say(Phrasebook.unknownPerson(name), priority: 0, category: "whereis")
    }

    /// Goodbye → offer to remember, only if a stranger is close, no flow is active and the cooldown passed.
    func goodbyeDetected(at t: TimeInterval) async {
        guard !consentActive, t - lastGoodbyeFlowAt >= goodbyeCooldown else { return }
        let strangerClose = perception.currentTracks().contains { !$0.identity.isKnown && $0.distance == .close }
        guard strangerClose else { return }
        lastGoodbyeFlowAt = t
        Task { await consentFlow.begin(confirmFirst: true) }
    }

    /// A sustained conversation with a stranger in view → offer to remember them. Same user-first confirmation as
    /// goodbyes, but any non-far stranger counts (people talk at arm's length or across a table) and a longer
    /// cooldown, so a "no" is not re-asked every minute of the same chat.
    func conversationDetected(at t: TimeInterval) async {
        guard !consentActive, t - lastConversationOfferAt >= conversationCooldown, t - lastGoodbyeFlowAt >= goodbyeCooldown else { return }
        let now = clock()
        guard let near = strangerNear, now - near.last <= nearGap, near.last - near.first >= faceToFaceSeconds else {
            let held = strangerNear.map { Int($0.last - $0.first) } ?? 0
            DiagnosticLog.write("conversation: someone new near for \(held) s of \(Int(faceToFaceSeconds)), not offering")
            return
        }
        // Who the consent flow will scan: facing the wearer first, then the largest face.
        let partner = perception.currentTracks()
            .filter { !$0.identity.isKnown && $0.distance != .far }
            .max { ($0.isFacingUser ? 1 : 0, $0.faceHeightPx) < ($1.isFacingUser ? 1 : 0, $1.faceHeightPx) }
        guard let partner else { DiagnosticLog.write("conversation: the new person is out of view, not offering"); return }
        let face = perception.bestEmbeddings(track: partner.trackID, max: 1).first?.vector
        if offeredTracks.contains(partner.trackID) || face.map({ f in offeredFaces.contains { Matcher.cosine($0, f) >= sameFaceCosine } }) == true {
            DiagnosticLog.write("conversation: already offered this person, not offering")
            return
        }
        offeredTracks.insert(partner.trackID)                           // once per person, whatever they answer
        if let face { offeredFaces.append(face) }
        DiagnosticLog.write("conversation: offering to add the person at \(partner.bearing.clock) o'clock")
        lastConversationOfferAt = t
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
