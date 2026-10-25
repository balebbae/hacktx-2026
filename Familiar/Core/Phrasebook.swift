import Foundation

/// Every spoken string in the app comes from here. No utterance may contain the word "Poyo" (the wake word).
/// Directions are clock positions from the true bearing (12 = straight ahead, 30° per hour).
enum Phrasebook {
    // MARK: Cues
    static func clock(_ b: Bearing) -> String { "\(b.clock) o'clock" }
    static func appeared(name: String, bearing: Bearing, distance: Distance) -> String { "\(name), \(clock(bearing)), \(distance.words)." }
    static func approaching(name: String, from bearing: Bearing) -> String {
        bearing.clock == 12 ? "\(name), coming toward you." : "\(name), coming from \(clock(bearing))."
    }
    static func arrived(name: String) -> String { "\(name), next to you." }
    static func left(name: String) -> String { "\(name) left." }
    static func unknownClose(bearing: Bearing) -> String { "Someone close, \(clock(bearing))." }
    static func speaking(name: String) -> String { "\(name)." }

    // MARK: Roll call
    static func rollCallKnown(name: String, bearing: Bearing, distance: Distance) -> String { appeared(name: name, bearing: bearing, distance: distance) }
    static func rollCallOthers(count: Int) -> String {
        switch count {
        case 0: return "No one else."
        case 1: return "One other person."
        default: return "\(count) other people."
        }
    }
    static func rollCallNoKnown(count: Int) -> String {
        count == 0 ? nobody : "No one I know. \(count) \(count == 1 ? "person" : "people")."
    }
    static let nobody = "I don't see anyone."

    // MARK: Consent
    static let shouldIAdd = "Should I add this person to your contacts?"
    static func wearerAsksCard(userName: String) -> String { "Do you want to be added to \(userName)'s contacts?" }
    static let scanningFace = "I'm going to scan your face."
    static let lookTowardMe = "Could you look toward me for a second?"
    static func consentQuestion(userName: String, name: String?) -> String {
        if let name, !name.isEmpty {
            return "\(userName) would like to recognize you next time you meet. Okay to remember your face, \(name)?"
        }
        return "\(userName) would like to recognize you next time you meet. Okay to remember your face?"
    }
    static let wasThatAYes = "Sorry, was that a yes?"
    static let whatShouldICallYou = "What should I call you?"
    static func saved(name: String) -> String { "Saved. \(name) is in your contacts." }
    static let nothingSaved = "Okay, nothing saved."
    static let theyLeft = "They seem to have left. Nothing saved."

    // MARK: Self-enroll (S10: the other person holds the phone and taps YES themselves)
    static let someoneIntroducing = "Someone is introducing themselves."
    static func selfEnrollIntro(userName: String) -> String { "\(userName) uses this app to recognize people who agree. Want them to remember you?" }
    static func selfEnrollConsent(name: String) -> String { "Okay to remember your face, \(name)? Only this phone keeps it. You can be removed any time." }
    static func selfEnrollHandBack(name: String) -> String { "Saved. \(name), hand the phone back." }
    static let lookAtCamera = "Look at the camera…"
    static func scanProgress(_ have: Int, of total: Int) -> String { "\(lookAtCamera) \(have)/\(total)" }
    static let noFaceYet = "No face yet. Hold the phone at arm's length."

    // MARK: Surroundings (on-device scene and hazards; never people)
    static func hazard(_ k: HazardKind) -> String {
        switch k {
        case .stairs: return "Stairs ahead."
        case .escalator: return "Escalator ahead."
        case .crosswalk: return "Crosswalk ahead."
        case .obstacle: return "Obstacle ahead."
        }
    }
    /// "1 meter", "3 meters" (whole meters, at least one).
    static func meters(_ m: Double) -> String {
        let n = max(1, Int(m.rounded()))
        return n == 1 ? "1 meter" : "\(n) meters"
    }
    /// Something in the walking path, from the vision reading: "Wall ahead, 2 meters." / "Chair, 1 o'clock, 2 meters."
    static func pathAlert(what: String?, bearing: Bearing, meters m: Double?) -> String {
        let thing = capitalized(what ?? "obstacle")
        let distance = m.map { ", \(meters($0))" } ?? ""
        return bearing.clock == 12 ? "\(thing) ahead\(distance)." : "\(thing), \(clock(bearing))\(distance)."
    }
    /// "Stairs down, 12 o'clock, 3 meters."
    static func sceneHazard(_ name: String, bearing: Bearing, meters m: Double?) -> String {
        "\(capitalized(name)), \(clock(bearing))\(m.map { ", \(meters($0))" } ?? "")."
    }
    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
    static func place(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() + "." }
    static let nothingToName = "Nothing I can name."

    // MARK: Commands
    static func mode(_ m: ChatterMode) -> String {
        switch m { case .quiet: return "Quiet mode."; case .normal: return "Normal mode."; case .chatty: return "Chatty mode." }
    }
    static let muted = "Muted."
    static let unmuted = "Unmuted."
    static func calling(name: String) -> String { "Calling \(name)." }
    static func texting(name: String) -> String { "Opening a message to \(name)." }
    static func unknownPerson(_ x: String) -> String { "I don't know anyone called \(x)." }
    static func notVisible(name: String) -> String { "I don't see \(name)." }
    static let didNotGetThat = "Sorry, I didn't get that."
}

extension Bearing {
    /// 12 + round(degrees / 30), wrapped to 1…12. The glasses see ±26°, so anything in view is 11, 12 or 1.
    var clock: Int {
        let h = Int((degrees / 30).rounded())
        return ((11 + h) % 12 + 12) % 12 + 1
    }
    /// A bearing at the centre of an hour, for prewarming and tests.
    static func atClock(_ hour: Int) -> Bearing {
        let offset = ((hour % 12) + 12) % 12          // 0 = 12 o'clock
        let deg = Double(offset > 6 ? offset - 12 : offset) * 30
        return Bearing(degrees: deg, band: deg < -7 ? .left : deg > 7 ? .right : .ahead)
    }
}

extension BearingBand {
    var words: String {
        switch self {
        case .farLeft: return "far left"
        case .left: return "left"
        case .ahead: return "ahead"
        case .right: return "right"
        case .farRight: return "far right"
        }
    }
    static let all: [BearingBand] = [.farLeft, .left, .ahead, .right, .farRight]
}

extension Distance {
    var words: String {
        switch self { case .close: return "close"; case .medium: return "medium"; case .far: return "far" }
    }
    static let all: [Distance] = [.close, .medium, .far]
}
