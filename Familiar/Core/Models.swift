import Foundation
import CoreGraphics

extension Identity {
    var name: String? { if case let .known(_, name, _) = self { return name }; return nil }
    var personID: UUID? { if case let .known(id, _, _) = self { return id }; return nil }
    var score: Float? {
        switch self { case let .known(_, _, s): return s; case let .unknown(s): return s }
    }
    var isKnown: Bool { personID != nil }
}

extension PerceptionEvent {
    /// Short, stable name used by `script.json`, `fixtures.json` and the judge view's event log.
    var kindName: String {
        switch self {
        case .snapshot: return "snapshot"
        case .knownAppeared: return "knownAppeared"
        case .knownApproaching: return "knownApproaching"
        case .knownArrived: return "knownArrived"
        case .knownLeft: return "knownLeft"
        case .unknownCountChanged: return "unknownCountChanged"
        case .speakingStarted: return "speakingStarted"
        case .cue: return "cue"
        }
    }
    var personName: String? {
        switch self {
        case let .knownAppeared(t), let .knownApproaching(t), let .knownArrived(t), let .speakingStarted(t): return t.identity.name
        case let .knownLeft(_, name, _): return name
        case let .cue(_, name, _): return name
        default: return nil
        }
    }
}

// MARK: - fixtures.json

struct FixtureManifest: Codable, Equatable {
    struct FOV: Codable, Equatable { var horizontalDegrees: Double; var verticalDegrees: Double }
    struct Clip: Codable, Equatable {
        var file: String
        var role: String?
        var person: String?
        var transcript: String?
        var expectKnown: [String]?
        var expectEvents: [String]?
        var onlyKnown: [String]?
        var maxKnownEvents: Int?
        var maxUnknownEvents: Int?
        var expectName: String?
        var expectGoodbye: Bool?
        var expectYesNo: String?
        var notes: String?
    }
    var fov: FOV
    var clips: [Clip]

    static func load(from bundle: Bundle = .main) -> FixtureManifest? {
        guard let url = bundle.url(forResource: "fixtures", withExtension: "json") else { return nil }
        return try? JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: url))
    }

    func clip(named file: String) -> Clip? { clips.first { $0.file == file || ($0.file as NSString).deletingPathExtension == file } }
}

// MARK: - script.json (ScriptedPerception)

struct ScriptEvent: Codable, Equatable {
    var t: TimeInterval
    var event: String            // knownAppeared | knownApproaching | knownArrived | knownLeft | unknownCountChanged | speakingStarted | cue
    var name: String?
    var band: String?            // farLeft | left | ahead | right | farRight
    var distance: String?        // close | medium | far
    var count: Int?
    var trackID: Int?
    var kind: String?            // wave | smile

    var bearingBand: BearingBand {
        switch band { case "farLeft": return .farLeft; case "left": return .left; case "right": return .right; case "farRight": return .farRight; default: return .ahead }
    }
    var distanceBin: Distance {
        switch distance { case "close": return .close; case "far": return .far; default: return .medium }
    }
}

extension BearingBand {
    /// Centre of the band in degrees for a given horizontal FOV (+ = right).
    func centerDegrees(hFOV: Double = 53) -> Double {
        switch self {
        case .farLeft: return -hFOV * 0.375
        case .left: return -hFOV * 0.1875
        case .ahead: return 0
        case .right: return hFOV * 0.1875
        case .farRight: return hFOV * 0.375
        }
    }
    /// Normalized horizontal centre of the band in the frame (0 = left edge, 1 = right edge).
    var frameCenterX: CGFloat {
        switch self { case .farLeft: return 0.125; case .left: return 0.3125; case .ahead: return 0.5; case .right: return 0.6875; case .farRight: return 0.875 }
    }
}

extension Distance {
    /// Face height as a fraction of frame height, roughly matching a 0.20 m face seen through an 85° vertical FOV.
    var typicalFaceHeightFraction: CGFloat {
        switch self { case .close: return 0.18; case .medium: return 0.09; case .far: return 0.05 }
    }
}
