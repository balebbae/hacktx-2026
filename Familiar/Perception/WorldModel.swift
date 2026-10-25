import Foundation

/// One line of text that says everything the phone knows right now: on-device people (names only for people
/// who agreed, strangers as a count) plus the latest vision reading. It is what the assistant reasons over.
enum WorldModel {
    static func contextLine(tracks: [TrackSnapshot], reading: SceneReading?, now: TimeInterval) -> String {
        var parts = [AgentToolRouter.sceneContext(tracks: tracks)]
        guard let r = reading else { return parts[0] + " No scene reading yet." }
        if let place = r.place { parts.append("Place: \(place).") }
        switch r.path {
        case .clear: parts.append("Path ahead clear.")
        case .caution, .blocked:
            parts.append("Path \(r.path.rawValue): \(r.pathWhat ?? "something") at \(Phrasebook.clock(r.bearing(r.pathX)))\(r.pathMeters.map { ", \(Phrasebook.meters($0))" } ?? "").")
        }
        func list(_ items: [SceneReading.Item]) -> String {
            items.map { "\($0.name) \(Phrasebook.clock(r.bearing($0.x)))\($0.meters.map { " \(Phrasebook.meters($0))" } ?? "")" }.joined(separator: "; ")
        }
        if !r.hazards.isEmpty { parts.append("Hazards: \(list(r.hazards)).") }
        if !r.objects.isEmpty { parts.append("Objects: \(list(r.objects)).") }
        if !r.signs.isEmpty { parts.append("Signs: \(r.signs.joined(separator: "; ")).") }
        parts.append("Scene seen \(max(0, Int((now - r.at).rounded()))) s ago.")
        return parts.joined(separator: " ")
    }
}
