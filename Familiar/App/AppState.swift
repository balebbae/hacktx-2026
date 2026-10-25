import Foundation
import SwiftUI
import QuartzCore

/// One line Familiar actually said, with the host-clock moment it reached playback. `MainTabView` feeds these from
/// whichever speaker is live (the `LogSpeaker` entries in the Simulator, `VoiceSpeaker.onSpoken` on a device), so
/// Today's Mimo, the nearby card's beam and the Room's cue ticker react to real speech, not only to the log feed.
struct SpokenCue: Identifiable, Equatable {
    let id: UUID
    let at: TimeInterval
    let utterance: Utterance

    init(utterance: Utterance, at: TimeInterval) {
        self.id = UUID()
        self.at = at
        self.utterance = utterance
    }
}

/// Small observable bag of user-facing state. Persisted with @AppStorage-style keys so it survives relaunches.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: ChatterMode { didSet { defaults.set(mode.rawStorage, forKey: "mode") } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }
    @Published var source: Services.Source { didSet { defaults.set(source.storageKey, forKey: "source") } }
    @Published var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    @Published var placeName: String { didSet { defaults.set(placeName, forKey: "placeName") } }
    @Published var speakLogSpeakerAloud: Bool { didSet { defaults.set(speakLogSpeakerAloud, forKey: "speakLogSpeakerAloud") } }
    /// How Familiar communicates: one preference, not a diagnosis. The root turns it into the `visionScale`
    /// environment value (`.visionProfile(state.visionProfile)`) so every size, weight, icon and hit target follows it.
    @Published var visionProfile: VisionProfile { didSet { defaults.set(visionProfile.rawValue, forKey: "visionProfile") } }

    /// The resolved scale for code that has no view environment (settings previews, spoken summaries).
    var visionScale: VisionScale { VisionScale.make(visionProfile) }

    /// The last few lines Familiar said, newest last. Not persisted. Survives `AppCoordinator.restart`, which clears
    /// the coordinator's own log feed, so the hero never forgets a cue because the demo script was re-run.
    @Published private(set) var spokenCues: [SpokenCue] = []

    var lastSpokenCue: SpokenCue? { spokenCues.last }

    /// Called by `MainTabView` for every utterance that reached playback, whichever speaker produced it.
    func noteSpoken(_ utterance: Utterance, at: TimeInterval = CACurrentMediaTime()) {
        spokenCues = Array(spokenCues.suffix(7)) + [SpokenCue(utterance: utterance, at: at)]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = ChatterMode(rawStorage: defaults.string(forKey: "mode")) ?? .normal
        muted = defaults.bool(forKey: "muted")
        source = Services.Source(storageKey: defaults.string(forKey: "source")) ?? Services.Source.defaultForThisDevice
        userName = defaults.string(forKey: "userName") ?? "Priya"
        placeName = defaults.string(forKey: "placeName") ?? "HackTX, UT Austin"
        speakLogSpeakerAloud = defaults.object(forKey: "speakLogSpeakerAloud") as? Bool ?? true
        visionProfile = VisionProfile(rawValue: defaults.string(forKey: "visionProfile") ?? "") ?? .balanced
    }
}

extension ChatterMode {
    var rawStorage: String { switch self { case .quiet: return "quiet"; case .normal: return "normal"; case .chatty: return "chatty" } }
    init?(rawStorage: String?) {
        switch rawStorage { case "quiet": self = .quiet; case "normal": self = .normal; case "chatty": self = .chatty; default: return nil }
    }
    var title: String { rawStorage.capitalized }
}
