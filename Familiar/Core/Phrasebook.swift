import Foundation

/// Every spoken string in the app comes from here. No utterance may contain the word "Familiar" (the wake word).
enum Phrasebook {
    // MARK: Cues
    static func appeared(name: String, band: BearingBand, distance: Distance) -> String { "\(name), \(band.words), \(distance.words)." }
    static func approaching(name: String, from band: BearingBand) -> String {
        switch band {
        case .left, .farLeft: return "\(name), coming from your left."
        case .right, .farRight: return "\(name), coming from your right."
        case .ahead: return "\(name), coming toward you."
        }
    }
    static func arrived(name: String) -> String { "\(name), next to you." }
    static func left(name: String) -> String { "\(name) left." }
    static func unknownClose(band: BearingBand) -> String {
        switch band {
        case .left, .farLeft: return "Someone close, on your left."
        case .right, .farRight: return "Someone close, on your right."
        case .ahead: return "Someone close, ahead."
        }
    }
    static func speaking(name: String) -> String { "\(name)." }

    // MARK: Roll call
    static func rollCallKnown(name: String, band: BearingBand, distance: Distance) -> String { appeared(name: name, band: band, distance: distance) }
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
    static let wantToRemember = "Want to remember them?"
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
