import Foundation
import SwiftUI

/// Small observable bag of user-facing state. Persisted with @AppStorage-style keys so it survives relaunches.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: ChatterMode { didSet { defaults.set(mode.rawStorage, forKey: "mode") } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }
    @Published var source: Services.Source { didSet { defaults.set(source.storageKey, forKey: "source") } }
    @Published var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    @Published var placeName: String { didSet { defaults.set(placeName, forKey: "placeName") } }
    @Published var speakLogSpeakerAloud: Bool { didSet { defaults.set(speakLogSpeakerAloud, forKey: "speakLogSpeakerAloud") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = ChatterMode(rawStorage: defaults.string(forKey: "mode")) ?? .normal
        muted = defaults.bool(forKey: "muted")
        source = Services.Source(storageKey: defaults.string(forKey: "source")) ?? Services.Source.defaultForThisDevice
        userName = defaults.string(forKey: "userName") ?? "Priya"
        placeName = defaults.string(forKey: "placeName") ?? "HackTX, UT Austin"
        speakLogSpeakerAloud = defaults.object(forKey: "speakLogSpeakerAloud") as? Bool ?? true
    }
}

extension ChatterMode {
    var rawStorage: String { switch self { case .quiet: return "quiet"; case .normal: return "normal"; case .chatty: return "chatty" } }
    init?(rawStorage: String?) {
        switch rawStorage { case "quiet": self = .quiet; case "normal": self = .normal; case "chatty": self = .chatty; default: return nil }
    }
    var title: String { rawStorage.capitalized }
}
