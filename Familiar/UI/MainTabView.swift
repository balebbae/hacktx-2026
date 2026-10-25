import SwiftUI
import QuartzCore

/// Today · Room · People · You. Owns the flow runtime and everything that must survive a tab switch:
/// the consent card, the readiness sheet, the volume-button trigger, the "just saved" detail sheet and the cue toast
/// that mirrors every spoken cue as text at the top of the screen. It is also the one place both speaker feeds meet:
/// every line that reached playback is recorded on `AppState.spokenCues`, so Today and Room react on a device too.
struct MainTabView: View {
    enum Tab: Hashable { case today, room, people, you }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var runtime = FlowRuntime()
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "whoIsHere"
    @AppStorage(YouSettings.cueTextStaysOnScreen) private var cueTextStaysOnScreen = false
    @State private var tab: Tab = .today
    @State private var showReadiness = false
    @State private var savedPerson: Person?
    @State private var toast: CueToastItem?
    @State private var previewConsentCard = ProcessInfo.processInfo.arguments.contains("-demoConsentCard")
    /// The `VoiceSpeaker` whose `onSpoken` already feeds us, so a re-emitted `services` never doubles the toast.
    @State private var mirroredSpeaker: ObjectIdentifier?

    var body: some View {
        tabs
            .tint(FamiliarPalette.ocean(scale))
            .environment(\.openReadiness, { showReadiness = true })
            .background(VolumeButtonObserver { pressed in
                guard pressed else { return }
                handleVolumePress()
            })
            .overlay(alignment: .top) { toastOverlay }
            .fullScreenCover(isPresented: consentCardShown) {
                ConsentCardView(state: runtime.consentState,
                                question: consentQuestion,
                                onAnswer: { yes in runtime.tapAnswer(yes: yes) },
                                onCancel: { runtime.cancelConsent() },
                                levelProvider: { Double(coordinator.services?.audioInput.micLevel ?? 0) })
            }
            .fullScreenCover(isPresented: $previewConsentCard) {
                ConsentCardView(state: .listening,
                                question: Phrasebook.consentQuestion(userName: state.userName, name: "Marcus"),
                                onAnswer: { _ in previewConsentCard = false },
                                onCancel: { previewConsentCard = false })
            }
            .sheet(isPresented: $showReadiness) { ReadinessView(onDone: { showReadiness = false; readinessDone = true }) }
            .sheet(item: $savedPerson) { person in
                NavigationStack { PersonDetailView(person: person).environmentObject(runtime) }
            }
            .onReceive(coordinator.$services) { services in
                guard let services else { return }
                runtime.bind(services: services, state: state, coordinator: coordinator)
                mirrorSpokenCues(of: services)
            }
            .onChange(of: runtime.lastSaved) { _, person in
                if let person { savedPerson = person }
            }
            .onChange(of: coordinator.utterances.last?.id) { _, _ in
                // The Simulator and the "log" voice: LogSpeaker entries arrive through the coordinator.
                if let entry = coordinator.utterances.last { noteSpoken(entry.utterance, at: entry.at) }
            }
            .task(id: toast?.id) { await dismissToastLater() }
            .onAppear { if !readinessDone { showReadiness = true } }
    }

    // MARK: - Tabs

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView().environmentObject(runtime) }
                .tabItem { Label("Today", systemImage: "sparkles") }
                .tag(Tab.today)
            NavigationStack { RoomView().environmentObject(runtime) }
                .tabItem { Label("Room", systemImage: "person.2") }
                .tag(Tab.room)
            NavigationStack { PeopleView().environmentObject(runtime) }
                .tabItem { Label("People", systemImage: "person.crop.rectangle.stack") }
                .tag(Tab.people)
            NavigationStack { YouView().environmentObject(runtime) }
                .tabItem { Label("You", systemImage: "person.circle") }
                .tag(Tab.you)
        }
    }

    /// The resolved scale from the root (`FamiliarApp` applies `.visionProfile(state.visionProfile)` to the whole tree).
    @Environment(\.visionScale) private var scale

    private var consentCardShown: Binding<Bool> {
        Binding<Bool>(get: { runtime.showsConsentCard },
                      set: { shown in if !shown { runtime.cancelConsent() } })
    }

    // MARK: - Cue toast

    /// A cue can be repeated from its toast (spec 20.5 §06) while a speaker exists to say it again.
    @ViewBuilder private var toastOverlay: some View {
        if let toast {
            toastView(toast)
                .id(toast.id)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 6)
                .onTapGesture { dismissToast() }
                .accessibilityAction { dismissToast() }
                .accessibilityAction(named: "Dismiss") { dismissToast() }
                .accessibilityHint("Double-tap to dismiss")
                .accessibilityHidden(scale.spokenFirst)
        }
    }

    private func toastView(_ item: CueToastItem) -> some View {
        var repeatAction: (() -> Void)? = nil
        if canRepeat(item) { repeatAction = { repeatCue(item) } }
        return CueToast(text: item.text,
                        systemImage: item.systemImage,
                        tint: item.tint,
                        edge: .top,
                        actionTitle: repeatAction == nil ? nil : "Repeat",
                        actionHint: "Says this cue again",
                        action: repeatAction)
    }

    /// On a device the speaker is a `VoiceSpeaker`, whose cues never reach `coordinator.utterances` (that feed is the
    /// LogSpeaker's). Its `onSpoken` fires off the main thread for every utterance that reached playback. The slot is
    /// a single closure, so any handler already there keeps running, and the same speaker is never wired twice.
    private func mirrorSpokenCues(of services: Services) {
        guard let voice = services.speaker as? VoiceSpeaker else { return }
        let identity = ObjectIdentifier(voice)
        guard identity != mirroredSpeaker else { return }
        mirroredSpeaker = identity
        let previous: ((VoiceSpeaker.Spoken) -> Void)? = voice.onSpoken
        voice.onSpoken = { (spoken: VoiceSpeaker.Spoken) in
            previous?(spoken)
            let utterance = spoken.utterance
            let at: TimeInterval = spoken.window?.lowerBound ?? CACurrentMediaTime()
            Task { @MainActor in noteSpoken(utterance, at: at) }
        }
    }

    /// Both feeds land here: the line is recorded on `AppState.spokenCues` (Today's Mimo and beam, Room's ticker),
    /// then mirrored as a toast when it was addressed to the wearer.
    private func noteSpoken(_ utterance: Utterance, at: TimeInterval) {
        state.noteSpoken(utterance, at: at)
        showToast(utterance)
    }

    /// Every utterance addressed to the wearer becomes a toast. Lines said to the other person during consent do not.
    /// The haptic follows the cue's meaning (`CueToastItem.haptic(for:)`); cues whose screen already played one get none.
    private func showToast(_ utterance: Utterance) {
        guard utterance.audience == .user else { return }
        let item = CueToastItem(utterance: utterance)
        withAnimation(CueToast.spring()) { toast = item }
        if let kind = CueToastItem.haptic(for: utterance.category) { FamiliarHaptics.play(kind) }
    }

    private func dismissToastLater() async {
        guard toast != nil, !cueTextStaysOnScreen else { return }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        dismissToast()
    }

    private func dismissToast() {
        withAnimation(CueToast.spring()) { toast = nil }
    }

    private func canRepeat(_ item: CueToastItem) -> Bool {
        item.utterance != nil && coordinator.services != nil
    }

    /// Says the toast's own line again through the live speaker. Not `.repeatLast`: the router only remembers its own
    /// answers (roll call, mode, where-is), never the presence cues the policy produced, so that path would say
    /// "Sorry, I didn't get that." for exactly the cues people want repeated.
    private func repeatCue(_ item: CueToastItem) {
        guard let utterance = item.utterance, let speaker = coordinator.services?.speaker else { return }
        FamiliarHaptics.play(.listen)
        coordinator.log("command repeat cue")
        Task { await speaker.speak(utterance) }
    }

    // MARK: - Actions

    private func whoIsHere() { if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() } }
    private func rememberThem() { if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() } }

    /// Spec 20.4: mute must be reachable from a fixed action. The volume button can now pause and resume cues.
    private func togglePause() {
        state.muted.toggle()
        coordinator.setMuted(state.muted)
        FamiliarHaptics.play(state.muted ? .paused : .accepted)
    }

    private func handleVolumePress() {
        switch volumePrimary {
        case "rememberThem": rememberThem()
        case "pauseCues": togglePause()
        default: whoIsHere()
        }
    }

    private var consentQuestion: String {
        if case let .asking(name) = runtime.consentState { return Phrasebook.consentQuestion(userName: state.userName, name: name) }
        return Phrasebook.consentQuestion(userName: state.userName, name: runtime.nameGuess?.name)
    }
}

/// Lets any screen open the readiness checklist (the device chip on Today uses it).
private struct OpenReadinessKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openReadiness: () -> Void {
        get { self[OpenReadinessKey.self] }
        set { self[OpenReadinessKey.self] = newValue }
    }
}

/// One cue toast: a fresh id per cue (so a repeated cue re-animates), its words, a symbol for the kind of cue, and
/// the utterance itself so "Repeat" can say exactly that line again.
struct CueToastItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let systemImage: String
    let tint: Color
    let utterance: Utterance?

    init(id: UUID, text: String, systemImage: String, tint: Color, utterance: Utterance? = nil) {
        self.id = id
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.utterance = utterance
    }

    init(utterance: Utterance) {
        self.init(id: UUID(),
                  text: utterance.text,
                  systemImage: CueToastItem.symbol(for: utterance.category),
                  tint: CueToastItem.tint(for: utterance.category),
                  utterance: utterance)
    }

    init(entry: LogSpeaker.Entry) {
        self.init(id: entry.id,
                  text: entry.utterance.text,
                  systemImage: CueToastItem.symbol(for: entry.utterance.category),
                  tint: CueToastItem.tint(for: entry.utterance.category),
                  utterance: entry.utterance)
    }

    static func symbol(for category: String) -> String {
        switch category {
        case "appeared", "approaching", "arrived", "speaking", "cue", "preview": return "person.wave.2"
        case "left": return "figure.walk"
        case "rollcall": return "person.2"
        case "consent": return "hand.raised"
        case "mode", "command": return "waveform"
        case "glasses": return "eyeglasses"
        case "whereis": return "location"
        default: return "sparkles"
        }
    }

    static func tint(for category: String) -> Color {
        switch category {
        case "left", "mode", "command", "glasses": return FamiliarPalette.inkSecondary
        default: return FamiliarPalette.ocean
        }
    }

    /// The haptic that means this cue. Presence cues are the double tap, a leaving cue the single softer one.
    /// Mode and command lines, consent lines, roll calls and previews return nil: the control that caused them
    /// already played its own pattern, or several lines arrive in a row and must not buzz each time.
    static func haptic(for category: String) -> HapticKind? {
        switch category {
        case "appeared", "approaching", "arrived", "speaking", "cue": return .cue
        case "left": return .left
        default: return nil
        }
    }
}

#Preview("Main tabs") {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(AppCoordinator())
}
