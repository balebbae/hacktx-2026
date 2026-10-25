import SwiftUI

/// Today: Mimo, one headline, one big action. Silence is the default, so the screen says little.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.openReadiness) private var openReadiness

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                MimoView(state: mimoState, size: 230)
                    .padding(.top, 8)
                VStack(spacing: 10) {
                    Eyebrow(text: state.muted ? "Paused" : "Awareness is on")
                    Text(headline)
                        .font(FamiliarType.titleXL)
                        .foregroundStyle(FamiliarPalette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    MimoStatusLine(state: mimoState, text: support)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 4)

                VStack(spacing: 12) {
                    Button { whoIsHere() } label: { Label("Who's here?", systemImage: "person.2.wave.2") }
                        .buttonStyle(PrimaryPillStyle())
                        .accessibilityHint("Says the known people around you, then counts the others")
                    HStack(spacing: 12) {
                        Button { state.muted.toggle(); coordinator.setMuted(state.muted) } label: {
                            Label(state.muted ? "Resume" : "Pause", systemImage: state.muted ? "play" : "pause")
                        }
                        .buttonStyle(GhostPillStyle())
                        .accessibilityHint(state.muted ? "Turns cues back on" : "Stops all cues except urgent ones")
                        Button { rememberThem() } label: { Label("Remember them", systemImage: "person.badge.plus") }
                            .buttonStyle(GhostPillStyle())
                            .disabled(runtime.showsConsentCard)
                            .accessibilityHint("Asks the person in front of you for permission to remember their face")
                    }
                    Picker("Cue level", selection: $state.mode) {
                        ForEach(ChatterMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Quiet says less, chatty says more")
                    .onChange(of: state.mode) { _, mode in coordinator.setMode(mode) }
                }
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 24)

                if let nearby = knownTracks.first {
                    NearbyPersonCard(name: nearby.identity.name ?? "", direction: nearby.bearing.band.words, distance: nearby.distance.words, score: nearby.identity.score)
                        .padding(.horizontal, FamiliarPalette.margin)
                        .padding(.top, 20)
                    Text("You can say hi first.")
                        .font(FamiliarType.supporting)
                        .foregroundStyle(FamiliarPalette.inkSecondary)
                        .padding(.top, 8)
                }

                consentStatus
                    .padding(.horizontal, FamiliarPalette.margin)
                    .padding(.top, 16)

                if let error = coordinator.lastError {
                    Text(error)
                        .font(FamiliarType.supporting)
                        .foregroundStyle(FamiliarPalette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
                        .padding(.horizontal, FamiliarPalette.margin)
                        .padding(.top, 12)
                        .accessibilityLabel("Last error: \(error)")
                }
                Spacer(minLength: 32)
            }
        }
        .familiarCanvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Familiar")
                .font(FamiliarType.title)
                .foregroundStyle(FamiliarPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: openReadiness) {
                StatusChip(text: deviceLabel, systemImage: deviceSymbol, tint: FamiliarPalette.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Device: \(deviceLabel). Opens the readiness checklist")
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, 12)
    }

    private var knownTracks: [TrackSnapshot] { coordinator.tracks.filter { $0.identity.isKnown } }

    private var mimoState: MimoState {
        if state.muted { return .paused }
        switch runtime.consentState {
        case .asking, .listening: return .waitingForConsent
        case .gathering: return .thinking
        case .saving: return .thinking
        case .done: return .success
        default: break
        }
        if let last = coordinator.utterances.last, CACurrentMediaTime() - last.at < 2.5 { return .speaking }
        if !knownTracks.isEmpty { return .cue }
        return .idle
    }

    private var headline: String {
        if state.muted { return "Awareness paused." }
        if !knownTracks.isEmpty { return "You're in good company." }
        return "Here with you."
    }

    private var support: String {
        if state.muted { return "Resume when you're ready." }
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

    private func statusRow(_ text: String, _ symbol: String, tint: Color = FamiliarPalette.inkSecondary) -> some View {
        Label(text, systemImage: symbol)
            .font(FamiliarType.supporting)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
    }

    private func whoIsHere() { if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() } }
    private func rememberThem() { if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() } }
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
