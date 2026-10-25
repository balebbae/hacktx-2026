import SwiftUI
import QuartzCore
import MetalFxKit
import BorderBeamKit

/// Today: Mimo on a soft aurora, one headline, one liquid-metal action. Silence is the default, so the screen says little.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.openReadiness) private var openReadiness
    @Environment(\.openIntroduce) private var openIntroduce
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(YouSettings.mimoPresence) private var mimoPresence = MimoPresence.full.rawValue

    /// True for six seconds after Familiar last said something about a person; the nearby card wears its beam while it is true.
    @State private var cueIsFresh = false
    /// True for 2.5 s after any utterance: Mimo's speaking pose. Driven by the same task, never by the clock inside `body`.
    @State private var isSpeaking = false
    @State private var errorShakes = 0

    private static let smallMove: Animation = .spring(response: 0.44, dampingFraction: 0.78)
    /// Spec Screen 06: a 245–275 pt Mimo is the whole emotional focus; the icon scale may grow it to 300 at low vision.
    private static let heroMimoSize: Double = 250
    /// The compact companion (spec 19.6 Settings: full, compact, hidden).
    private static let compactMimoSize: Double = 120

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                hero
                actions
                    .padding(.horizontal, FamiliarPalette.margin)
                    .padding(.top, 24)
                nearby
                consentStatus
                    .padding(.horizontal, FamiliarPalette.margin)
                    .padding(.top, 16)
                errorCard
                motto
                Spacer(minLength: 32)
            }
        }
        .familiarCanvas()
        .toolbar(.hidden, for: .navigationBar)
        // `AppState.spokenCues` is fed by both speaker feeds (MainTabView), so this fires on a device too.
        .task(id: state.lastSpokenCue?.id) { await trackCueFreshness() }
        .onChange(of: coordinator.lastError) { _, newValue in
            if newValue != nil { errorShakes += 1 }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Familiar")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: openReadiness) {
                StatusChip(text: deviceLabel, systemImage: deviceSymbol, tint: FamiliarPalette.ink(scale))
                    .visionHitTarget(scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Device: \(deviceLabel)")
            .accessibilityHint("Opens the readiness checklist")
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, 12)
    }

    // MARK: - Hero

    /// You → Accessibility → Mimo: full stage, a small companion, or no Mimo (the aurora goes with it; the words stay).
    private var presence: MimoPresence { MimoPresence.stored(mimoPresence) }

    private var showsAurora: Bool { !scale.highContrast && !reduceTransparency && presence != .hidden }

    private var mimoSize: Double { presence == .compact ? Self.compactMimoSize : Self.heroMimoSize }

    /// The orb Mimo draws at this profile (same cap as `MimoView`), so the aurora can stop exactly where Mimo ends.
    private var heroOrbSize: Double { mimoSize * Double(min(1.2, scale.iconScale)) }

    /// Mimo's own frame is orb × 1.2 tall plus 8 pt of top padding; the aurora never reaches below it, so no gradient
    /// ever sits behind the eyebrow, the headline or the status line.
    private var auroraHeight: CGFloat { CGFloat(heroOrbSize * 1.2) + 8 }

    private var hero: some View {
        ZStack(alignment: .top) {
            if showsAurora {
                AuroraBackground(intensity: auroraIntensity, mood: auroraMood)
                    .frame(height: auroraHeight)
                    .mask { auroraMask }
                    .accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                if presence != .hidden {
                    MimoView(state: mimoState, size: mimoSize)
                        .padding(.top, 8)
                }
                heroText
            }
            .padding(.top, presence == .hidden ? 20 : 0)
            .padding(.bottom, 12)
        }
        .animation(scale.simplifyMotion ? nil : Animation.easeInOut(duration: 0.6), value: mimoState)
    }

    private var auroraMask: some View {
        LinearGradient(stops: [
            Gradient.Stop(color: Color.black, location: 0),
            Gradient.Stop(color: Color.black, location: 0.55),
            Gradient.Stop(color: Color.clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var heroText: some View {
        VStack(spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(headline)
                .font(FamiliarType.display(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
            MimoStatusLine(state: mimoState, text: support)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow). \(headline) \(support)")
        .accessibilitySortPriority(scale.spokenFirst ? 10 : 0)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            whoIsHereButton
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pauseButton
                    rememberButton
                }
                VStack(spacing: 12) {
                    pauseButton
                    rememberButton
                }
            }
            introduceRow
            cueLevel
                .padding(.top, 6)
        }
    }

    /// Hands the phone to the other person: they read, look at the camera and tap YES themselves.
    private var introduceRow: some View { introduceButton }

    private var introduceButton: some View {
        Button { openIntroduce() } label: {
            Label("Introduce yourself", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(GhostPillStyle())
        .disabled(coordinator.services == nil)
        .accessibilityHint("Hand the phone to the other person so they can add themselves with their own tap")
    }

    /// The one liquid-metal control on the screen: a chromatic ring that bends with the phone's tilt.
    private var whoIsHereButton: some View {
        MetalFx(variant: .button,
                preset: .chromatic,
                theme: .auto,
                cornerRadius: Double(scale.hitTarget / 2),
                paused: scale.simplifyMotion,
                id: "who-is-here") {
            Button { whoIsHere() } label: {
                Label("Who's here?", systemImage: "person.2.wave.2")
            }
            .buttonStyle(PrimaryPillStyle())
            .accessibilityHint("Says the known people around you, then counts the others")
        }
    }

    private var pauseButton: some View {
        Button { togglePause() } label: {
            Label(state.muted ? "Resume" : "Pause", systemImage: state.muted ? "play" : "pause")
        }
        .buttonStyle(GhostPillStyle())
        .accessibilityLabel(state.muted ? "Resume awareness" : "Pause awareness")
        .accessibilityHint(state.muted ? "Turns cues back on" : "Stops all cues except urgent ones")
    }

    private var rememberButton: some View {
        Button { rememberThem() } label: {
            Label("Remember them", systemImage: "person.badge.plus")
        }
        .buttonStyle(GhostPillStyle())
        .disabled(runtime.showsConsentCard)
        .accessibilityHint("Asks the person in front of you for permission to remember their face")
    }

    private var cueOptions: [(ChatterMode, String)] {
        ChatterMode.allCases.map { (mode: ChatterMode) -> (ChatterMode, String) in (mode, mode.title) }
    }

    private var cueLevel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Cue level")
                .padding(.leading, 6)
                .accessibilityHidden(true)
            // Voice commands change the mode and speak for themselves; only a tap here should speak.
            SlidingPillSegment(options: cueOptions,
                               selection: Binding(get: { state.mode }, set: { state.mode = $0; coordinator.setMode($0) }),
                               label: "Cue level")
            Text("Quiet says less, chatty says more.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .padding(.leading, 6)
        }
    }

    // MARK: - Nearby

    /// The closest known person, with Call when they left a phone number (spec 19.6 Home). The beam rides the card
    /// for six seconds after a cue; the whole card tilts gently under a finger (`tilt3D`, still under Reduce Motion).
    @ViewBuilder private var nearby: some View {
        VStack(spacing: 8) {
            if let track = knownTracks.first {
                nearbyCard(for: track)
                    .borderBeam(.md, colorVariant: .ocean, theme: .auto, active: cueIsFresh, borderRadius: 26)
                    .tilt3D()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Text("You can say hi first.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, knownTracks.isEmpty ? 0 : 20)
        .cardResize()
        .animation(scale.simplifyMotion ? nil : Self.smallMove, value: knownTracks.first?.trackID)
    }

    private func nearbyCard(for track: TrackSnapshot) -> some View {
        let name: String = track.identity.name ?? ""
        var action: (() -> Void)? = nil
        if let person = callablePerson(for: track) {
            action = { call(person) }
        }
        return NearbyPersonCard(name: name,
                                direction: track.bearing.band.words,
                                distance: track.distance.words,
                                score: track.identity.score,
                                actionTitle: action == nil ? nil : "Call",
                                action: action,
                                actionHint: "Opens the phone dialer for \(name). Nothing is dialed automatically")
    }

    /// The remembered person behind a track, only when a phone number is stored (the card shows no dead button).
    private func callablePerson(for track: TrackSnapshot) -> Person? {
        guard let id = track.identity.personID, runtime.router != nil else { return nil }
        guard let person = runtime.people.first(where: { $0.id == id }) else { return nil }
        let phone: String = (person.phone ?? "").trimmingCharacters(in: .whitespaces)
        return phone.isEmpty ? nil : person
    }

    /// Same path as Person detail: the dialer opens, nothing is dialed for the wearer.
    private func call(_ person: Person) {
        FamiliarHaptics.play(.accepted)
        runtime.router?.callDirect(person)
    }

    // MARK: - Status, error, motto

    @ViewBuilder private var consentStatus: some View {
        switch runtime.consentState {
        case .idle: EmptyView()
        case .confirmingWithUser: statusRow("Say yes to start remembering", "questionmark.bubble")
        case .gathering: statusRow("Looking at them…", "viewfinder")
        case .asking, .listening, .saving: statusRow("Asking for permission…", "waveform")
        case let .done(person): statusRow("\(person.name) chose to connect.", "checkmark.circle", tint: FamiliarPalette.success)
        case .declined: statusRow("They said no. Nothing saved.", "xmark.circle")
        case let .cancelled(reason): statusRow("Cancelled: \(reason)", "xmark.circle")
        }
    }

    private func statusRow(_ text: String, _ symbol: String, tint: Color? = nil) -> some View {
        let color: Color = tint ?? FamiliarPalette.inkSecondary(scale)
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .visionIcon(scale, base: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarType.supporting(scale))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var errorCard: some View {
        if let error = coordinator.lastError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .visionIcon(scale, base: 18)
                    .accessibilityHidden(true)
                Text(error)
                    .font(FamiliarType.supporting(scale))
            }
            .foregroundStyle(FamiliarPalette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
            .errorShake(trigger: errorShakes)
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.top, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last error: \(error)")
        }
    }

    private var motto: some View {
        Text("The finer things in life are felt, not seen.")
            .font(FamiliarType.micro(scale))
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .multilineTextAlignment(.center)
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.top, 28)
    }

    // MARK: - Derived state

    /// Frames are arriving from a started pipeline. Before that (first launch, a failed start, the test host) the
    /// screen says so instead of pretending to watch the room.
    private var awarenessLive: Bool { coordinator.services != nil && coordinator.fps > 0 }

    private var knownTracks: [TrackSnapshot] {
        guard awarenessLive else { return [] }
        return coordinator.tracks.filter { $0.identity.isKnown }
    }

    private var mimoState: MimoState {
        if state.muted { return .paused }
        if !awarenessLive { return .disconnected }
        switch runtime.consentState {
        case .asking, .listening: return .waitingForConsent
        case .gathering: return .thinking
        case .saving: return .thinking
        case .done: return .success
        default: break
        }
        if isSpeaking { return .speaking }
        if !knownTracks.isEmpty { return .cue }
        return .idle
    }

    /// The aurora follows Mimo: calm by default, cooler while listening or thinking, warm for a known person, silver
    /// and still when paused or waiting for the camera.
    private var auroraMood: AuroraMood {
        switch mimoState {
        case .listening, .waitingForConsent, .thinking: return .listening
        case .cue, .success, .speaking: return .cue
        case .paused, .disconnected: return .paused
        case .idle, .uncertain: return .calm
        }
    }

    private var auroraIntensity: Double {
        switch mimoState {
        case .paused, .disconnected: return 0.35
        case .cue, .success: return 1
        default: return 0.8
        }
    }

    private var eyebrow: String {
        if state.muted { return "Paused" }
        if !awarenessLive { return "Waiting for the camera" }
        return "Awareness is on"
    }

    private var headline: String {
        if state.muted { return "Awareness paused." }
        if !awarenessLive { return "Ready when you are." }
        if !knownTracks.isEmpty { return "You're in good company." }
        return "Here with you."
    }

    private var support: String {
        if state.muted { return "Resume when you're ready." }
        if !awarenessLive { return "No frames yet. The device chip above opens the checklist." }
        if let nearby = knownTracks.first, let name = nearby.identity.name {
            return "\(name), \(nearby.bearing.band.words), \(nearby.distance.words)."
        }
        return "Ask who's here, or simply enjoy the moment."
    }

    private var deviceLabel: String {
        switch state.source {
        case .glasses: return "Glasses"
        case .phone: return "Phone camera"
        case .fixture: return "Demo clip"
        }
    }

    private var deviceSymbol: String {
        switch state.source {
        case .glasses: return "eyeglasses"
        case .phone: return "iphone"
        case .fixture: return "film"
        }
    }

    // MARK: - Actions

    private func whoIsHere() {
        FamiliarHaptics.play(.listen)
        if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() }
    }

    private func rememberThem() {
        FamiliarHaptics.play(.accepted)
        if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() }
    }

    private func togglePause() {
        state.muted.toggle()
        coordinator.setMuted(state.muted)
        FamiliarHaptics.play(state.muted ? .paused : .accepted)
    }

    /// A line for the wearer about a person: a presence or movement cue, a roll call or a "where is" answer. Not
    /// "Muted.", not a mode change, and not the questions Familiar asks the other person.
    private static func isPersonCue(_ utterance: Utterance) -> Bool {
        guard utterance.audience == .user, utterance.category != "left" else { return false }
        return utterance.personID != nil || utterance.category == "rollcall" || utterance.category == "whereis"
    }

    /// Runs whenever Familiar says something new (either speaker: `AppState.spokenCues` is fed by `MainTabView` from
    /// the LogSpeaker log and from `VoiceSpeaker.onSpoken`). Mimo speaks for 2.5 s from the utterance; when the line
    /// was about a person, the nearby card's beam stays on for six seconds from the same moment.
    private func trackCueFreshness() async {
        guard let last = state.lastSpokenCue else {
            isSpeaking = false
            cueIsFresh = false
            return
        }
        let age = CACurrentMediaTime() - last.at
        let aboutSomeone = Self.isPersonCue(last.utterance)
        isSpeaking = age < 2.5
        cueIsFresh = aboutSomeone && age < 6
        if isSpeaking {
            try? await Task.sleep(for: .seconds(max(0, 2.5 - age)))
            guard !Task.isCancelled else { return }
            isSpeaking = false
        }
        if cueIsFresh {
            let remaining = 6 - (CACurrentMediaTime() - last.at)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            cueIsFresh = false
        }
    }
}

extension AudioRoute {
    var title: String {
        switch self {
        case .phoneMicGlassesA2DP: return "phone mic + glasses"
        case .glassesHFP: return "glasses HFP"
        case .glassesStreamMic: return "glasses stream mic"
        case .phoneOnly: return "phone only"
        }
    }
}

#Preview("Today") {
    HomeView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "HomeViewPreview") ?? .standard))
        .environmentObject(AppCoordinator())
        .environmentObject(FlowRuntime())
}

#Preview("Today, low vision") {
    HomeView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "HomeViewPreviewLowVision") ?? .standard))
        .environmentObject(AppCoordinator())
        .environmentObject(FlowRuntime())
        .environment(\.visionScale, VisionScale.make(.lowVision))
}
