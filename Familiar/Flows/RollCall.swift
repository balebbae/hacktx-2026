import Foundation

/// "Who's here": known people left → right ("{Name}, {band}, {distance}."), then a count of everyone else.
enum RollCall {
    static func phrase(tracks: [TrackSnapshot]) -> String {
        guard !tracks.isEmpty else { return Phrasebook.nobody }
        let known = tracks.filter { $0.identity.isKnown }.sorted { $0.bearing.degrees < $1.bearing.degrees }
        let others = tracks.count - known.count
        guard !known.isEmpty else { return Phrasebook.rollCallNoKnown(count: others) }
        var seen = Set<UUID>()
        let parts = known.compactMap { t -> String? in
            guard let pid = t.identity.personID, let name = t.identity.name, seen.insert(pid).inserted else { return nil }
            return Phrasebook.rollCallKnown(name: name, band: t.bearing.band, distance: t.distance)
        }
        let duplicates = known.count - parts.count
        return (parts + [Phrasebook.rollCallOthers(count: others + duplicates)]).joined(separator: " ")
    }

    static func utterance(tracks: [TrackSnapshot]) -> Utterance {
        Utterance(text: phrase(tracks: tracks), priority: 0, category: "rollcall", personID: nil, dedupeKey: "rollcall", audience: .user, earcon: true)
    }
}
