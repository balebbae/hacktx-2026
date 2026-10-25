import Foundation
import os

/// Turns perception events into utterances following AGENTS.md. Pure with respect to `now` (the caller's clock);
/// the only state is per-person cooldown bookkeeping, protected by a lock.
///
/// Mode gating:   quiet  = appeared, arrived
///                normal = quiet + approaching, left, speaking
///                chatty = normal + "someone close" for strangers
/// Cooldowns:     appeared 30 s, and never for someone seen in the last 8 s (tracks flicker) · approaching 20 s (and never within 5 s after an arrival) · arrived 30 s ·
///                left only if the person was close within the last 120 s · unknown close 20 s · speaking once per track
///                (S7: priority 1, played −6 dB via `SpeakerVolumeHint`; `ActiveSpeaker` already gates by person).
/// `approaching` and `arrived` share a dedupeKey so an arrival within 5 s replaces a still-queued approach.
/// No earcon: the chime is reserved for safety alerts and "heard you", so one sound means one thing.
final class FamiliarCuePolicy: CuePolicy, @unchecked Sendable {
    struct Cooldowns {
        var appeared: TimeInterval = 30
        var approaching: TimeInterval = 20
        var arrived: TimeInterval = 30
        var leftWindow: TimeInterval = 120
        var unknownClose: TimeInterval = 20
        var approachSuppressionAfterArrival: TimeInterval = 5
        /// Tracks flicker in a crowd (a head turn, someone walking between; 1–6 s gaps in a real session): a person
        /// seen this recently is not announced again. Someone who really left and came back is.
        var reappearAfter: TimeInterval = 8
    }

    private struct PersonState {
        var lastAppeared: TimeInterval?
        var lastApproaching: TimeInterval?
        var lastArrived: TimeInterval?
        var lastClose: TimeInterval?
        var lastSeen: TimeInterval?
    }
    private struct State {
        var people: [UUID: PersonState] = [:]
        var spokenTracks: Set<Int> = []
        var lastUnknownClose: TimeInterval?
        var unknownCloseTracks: [Int: TimeInterval] = [:]
    }

    let cooldowns: Cooldowns
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(cooldowns: Cooldowns = Cooldowns()) { self.cooldowns = cooldowns }

    func reset() { state.withLock { $0 = State() } }

    func utterances(for e: PerceptionEvent, mode: ChatterMode, now: TimeInterval) -> [Utterance] {
        state.withLock { s in
            switch e {
            case let .knownAppeared(t):
                guard case let .known(pid, name, _) = t.identity else { return [] }
                var p = s.people[pid] ?? PersonState()
                if t.distance == .close { p.lastClose = now }
                let seenRecently = p.lastSeen.map { now - $0 < cooldowns.reappearAfter } ?? false
                p.lastSeen = now
                defer { s.people[pid] = p }
                if seenRecently { return [] }
                if let last = p.lastAppeared, now - last < cooldowns.appeared { return [] }
                p.lastAppeared = now
                return [cue(Phrasebook.appeared(name: name, bearing: t.bearing, distance: t.distance), pid, "appeared", priority: 1)]

            case let .knownApproaching(t):
                guard case let .known(pid, name, _) = t.identity else { return [] }
                var p = s.people[pid] ?? PersonState()
                if t.distance == .close { p.lastClose = now }
                defer { s.people[pid] = p }
                guard mode != .quiet else { return [] }
                if let last = p.lastApproaching, now - last < cooldowns.approaching { return [] }
                if let arrived = p.lastArrived, now - arrived < cooldowns.approachSuppressionAfterArrival { return [] }
                p.lastApproaching = now
                return [cue(Phrasebook.approaching(name: name, from: t.bearing), pid, "approaching", priority: 1, dedupeKey: "move:\(pid.uuidString)")]

            case let .knownArrived(t):
                guard case let .known(pid, name, _) = t.identity else { return [] }
                var p = s.people[pid] ?? PersonState()
                p.lastClose = now
                defer { s.people[pid] = p }
                if let last = p.lastArrived, now - last < cooldowns.arrived { return [] }
                p.lastArrived = now
                return [cue(Phrasebook.arrived(name: name), pid, "arrived", priority: 1, dedupeKey: "move:\(pid.uuidString)")]

            case let .knownLeft(pid, name, _):
                guard mode != .quiet else { return [] }
                guard let close = s.people[pid]?.lastClose, now - close <= cooldowns.leftWindow else { return [] }
                s.people[pid]?.lastClose = nil
                return [cue(Phrasebook.left(name: name), pid, "left", priority: 2)]

            case let .speakingStarted(t):
                guard mode != .quiet, case let .known(pid, name, _) = t.identity else { return [] }
                guard s.spokenTracks.insert(t.trackID).inserted else { return [] }
                return [cue(Phrasebook.speaking(name: name), pid, "speaking", priority: 1, dedupeKey: "speaking:\(pid.uuidString)")]   // S7

            case let .snapshot(tracks, _):
                for t in tracks {
                    guard case let .known(pid, _, _) = t.identity else { continue }
                    if s.people[pid]?.lastAppeared != nil { s.people[pid]?.lastSeen = now }   // only people already announced
                    if t.distance == .close { s.people[pid, default: PersonState()].lastClose = now }
                }
                guard mode == .chatty else { return [] }
                let strangers = tracks.filter { !$0.identity.isKnown && $0.distance == .close }
                guard let first = strangers.min(by: { abs($0.bearing.degrees) < abs($1.bearing.degrees) }) else { return [] }
                if let last = s.lastUnknownClose, now - last < cooldowns.unknownClose { return [] }
                if let last = s.unknownCloseTracks[first.trackID], now - last < cooldowns.unknownClose * 3 { return [] }
                s.lastUnknownClose = now
                s.unknownCloseTracks[first.trackID] = now
                return [cue(Phrasebook.unknownClose(bearing: first.bearing), nil, "unknownClose", priority: 3, dedupeKey: "unknownClose")]

            case .unknownCountChanged, .cue:
                return []
            }
        }
    }

    private func cue(_ text: String, _ pid: UUID?, _ category: String, priority: Int, dedupeKey: String? = nil) -> Utterance {
        Utterance(text: text, priority: priority, category: category, personID: pid, dedupeKey: dedupeKey ?? "\(category):\(pid?.uuidString ?? "")", audience: .user, earcon: false)
    }
}
