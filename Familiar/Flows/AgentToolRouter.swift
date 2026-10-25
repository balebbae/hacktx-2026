import Foundation
import QuartzCore

// S8 — client tools the ElevenLabs agent may call. Every string the agent speaks back comes from `Phrasebook`,
// so the privacy rules (count strangers, never describe them, never speak for the user) hold here too.

/// One client-tool call as the agent sent it (name + JSON parameters), independent of the SDK type.
struct AgentToolCall {
    let id: String
    let name: String
    let parameters: [String: Any]

    init(id: String = UUID().uuidString, name: String, parameters: [String: Any] = [:]) {
        self.id = id; self.name = name; self.parameters = parameters
    }

    func string(_ key: String) -> String? {
        guard let v = parameters[key] else { return nil }
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        return "\(v)"
    }
}

/// What goes back to the agent. `endsSession` makes `AgentSession` hang up right after sending the result and then
/// run `afterEnd` (used by `remember_them`, whose consent flow needs the microphone the agent was holding).
struct AgentToolResult {
    let text: String
    var isError = false
    var endsSession = false
    var afterEnd: (@MainActor () async -> Void)? = nil
}

@MainActor
final class AgentToolRouter {
    static let toolNames = ["who_is_here", "where_is", "remember_them", "set_mode", "call_person", "text_person", "mute"]

    private let perception: Perception
    private let peopleStore: PeopleStore
    private let contacts: ContactsBridge
    private let consentFlow: ConsentFlow
    private let cueGate: CueGate
    private let setMode: (ChatterMode) -> Void
    private let setMuted: (Bool) -> Void
    private let lastSeen: () -> [UUID: LastSeen]
    private let rollCall: ([TrackSnapshot]) -> String
    private(set) var handled: [String] = []

    init(perception: Perception, peopleStore: PeopleStore, contacts: ContactsBridge, consentFlow: ConsentFlow, cueGate: CueGate,
         setMode: @escaping (ChatterMode) -> Void, setMuted: @escaping (Bool) -> Void,
         lastSeen: @escaping () -> [UUID: LastSeen] = { [:] },
         rollCall: @escaping ([TrackSnapshot]) -> String = RollCall.phrase(tracks:)) {
        self.perception = perception; self.peopleStore = peopleStore; self.contacts = contacts; self.consentFlow = consentFlow
        self.cueGate = cueGate; self.setMode = setMode; self.setMuted = setMuted; self.lastSeen = lastSeen; self.rollCall = rollCall
    }

    func handle(_ call: AgentToolCall) async -> AgentToolResult {
        handled.append(call.name)
        switch call.name {
        case "who_is_here":
            return AgentToolResult(text: rollCall(perception.currentTracks()))

        case "where_is":
            guard let name = call.string("name") else { return AgentToolResult(text: Phrasebook.didNotGetThat, isError: true) }
            return AgentToolResult(text: whereIs(name))

        case "remember_them":
            let flow = consentFlow
            return AgentToolResult(text: "Starting.", endsSession: true, afterEnd: { await flow.begin(confirmFirst: false) })

        case "set_mode":
            guard let m = ChatterMode(agentWord: call.string("mode") ?? "") else {
                return AgentToolResult(text: "Modes are quiet, normal or chatty.", isError: true)
            }
            setMode(m)
            return AgentToolResult(text: Phrasebook.mode(m))

        case "call_person":
            guard let name = call.string("name") else { return AgentToolResult(text: Phrasebook.didNotGetThat, isError: true) }
            guard let p = peopleStore.find(name: name) else { return AgentToolResult(text: Phrasebook.unknownPerson(name)) }
            contacts.call(p)                               // opens the dialer; the wearer taps call
            return AgentToolResult(text: Phrasebook.calling(name: p.name))

        case "text_person":
            guard let name = call.string("name") else { return AgentToolResult(text: Phrasebook.didNotGetThat, isError: true) }
            guard let p = peopleStore.find(name: name) else { return AgentToolResult(text: Phrasebook.unknownPerson(name)) }
            contacts.text(p)                               // opens Messages; nothing is sent
            return AgentToolResult(text: Phrasebook.texting(name: p.name))

        case "mute":
            cueGate.muted = true
            setMuted(true)
            return AgentToolResult(text: Phrasebook.muted)

        default:
            return AgentToolResult(text: "Unknown tool \(call.name).", isError: true)
        }
    }

    /// Same lookup order as `CommandRouter.whereIs`: visible track → last seen → known but not visible → unknown name.
    private func whereIs(_ name: String) -> String {
        let needle = name.lowercased()
        let tracks = perception.currentTracks()
        if let t = tracks.first(where: { ($0.identity.name ?? "").lowercased().hasPrefix(needle) }), let n = t.identity.name {
            return Phrasebook.rollCallKnown(name: n, band: t.bearing.band, distance: t.distance)
        }
        if let seen = lastSeen().values.filter({ $0.name.lowercased().hasPrefix(needle) }).max(by: { $0.at < $1.at }) {
            return Phrasebook.lastSeen(name: seen.name, band: seen.bearing.band)
        }
        if let p = peopleStore.find(name: name) { return Phrasebook.notVisible(name: p.name) }
        return Phrasebook.unknownPerson(name)
    }

    /// Silent context pushed to the agent every couple of seconds, e.g. "Visible now: Marcus ahead close; 2 other people."
    func sceneContext() -> String { Self.sceneContext(tracks: perception.currentTracks()) }

    static func sceneContext(tracks: [TrackSnapshot]) -> String {
        var names: [String] = []
        var seen = Set<UUID>()
        var others = 0
        for t in tracks.sorted(by: { $0.bearing.degrees < $1.bearing.degrees }) {
            if case let .known(pid, name, _) = t.identity {
                if seen.insert(pid).inserted { names.append("\(name) \(t.bearing.band.words) \(t.distance.words)") }
            } else { others += 1 }
        }
        if names.isEmpty && others == 0 { return "Visible now: no one." }
        var parts = names
        parts.append(others == 1 ? "1 other person" : "\(others) other people")
        return "Visible now: " + parts.joined(separator: "; ") + "."
    }
}

extension ChatterMode {
    /// Accepts "quiet" / "normal" / "chatty" (any case, surrounding punctuation ignored).
    init?(agentWord: String) {
        let w = agentWord.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        switch w {
        case "quiet", "silent", "off": self = .quiet
        case "normal", "default": self = .normal
        case "chatty", "verbose", "talkative": self = .chatty
        default: return nil
        }
    }
}
