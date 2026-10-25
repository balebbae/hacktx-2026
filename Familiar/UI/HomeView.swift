import SwiftUI

/// Home: one glance (or one VoiceOver swipe) tells the wearer whether the app is listening, then the two big actions.
/// All wiring (readiness sheet, consent cover, volume buttons, runtime binding) is unchanged from the skeleton.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var runtime = FlowRuntime()
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "whoIsHere"
    @State private var showReadiness = false
    @State private var detailPerson: Person?
    @State private var showDetail = false
    @State private var previewConsentCard = ProcessInfo.processInfo.arguments.contains("-demoConsentCard")

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    BigActionButton(title: "Who's here?",
                                    subtitle: "Known people, then a count of the rest",
                                    systemImage: "person.2.wave.2",
                                    tint: FamiliarTheme.known) { whoIsHere() }
                    BigActionButton(title: "Remember them",
                                    subtitle: "Asks the person in front of you for permission",
                                    systemImage: "person.badge.plus",
                                    tint: FamiliarTheme.consent,
                                    isEnabled: !runtime.showsConsentCard) { rememberThem() }
                    modeCard
                    sourceCard
                    LazyVGrid(columns: columns, spacing: 12) {
                        GlassTile(title: "Judge view", systemImage: "eye", detail: "Preview, cues, log",
                                  hint: "Shows the camera preview, cues and the event log") { JudgeView().environmentObject(runtime) }
                        GlassTile(title: "People", systemImage: "person.crop.rectangle.stack", detail: "\(runtime.people.count) remembered",
                                  hint: "Everyone who agreed to be remembered") { PeopleView().environmentObject(runtime) }
                        GlassTile(title: "Settings", systemImage: "gear", detail: "Voice, thresholds, keys",
                                  hint: "Your name, voice, thresholds and keys") { SettingsView().environmentObject(runtime) }
                        GlassTile(title: "Demo controls", systemImage: "wand.and.stars", detail: "Scripted helpers",
                                  hint: "Scripted demo helpers for the Simulator") { DemoControlsView().environmentObject(runtime) }
                    }
                    Button { showReadiness = true } label: {
                        Label("Readiness check", systemImage: "checklist")
                            .font(.familiarBody.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                    .glassCard(radius: 18)
                    .accessibilityHint("Checks permissions, model and keys")
                    if let error = coordinator.lastError {
                        Text(error)
                            .font(.familiarCaption)
                            .foregroundStyle(FamiliarTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCard(radius: 18, tint: FamiliarTheme.danger.opacity(0.3))
                            .accessibilityLabel("Last error: \(error)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .familiarScreen()
            .navigationTitle("Familiar")
            .navigationDestination(isPresented: $showDetail) {
                if let person = detailPerson { PersonDetailView(person: person).environmentObject(runtime) }
            }
        }
        .background(VolumeButtonObserver { pressed in
            guard pressed else { return }
            if volumePrimary == "rememberThem" { rememberThem() } else { whoIsHere() }
        })
        .fullScreenCover(isPresented: Binding(get: { runtime.showsConsentCard }, set: { if !$0 { runtime.cancelConsent() } })) {
            ConsentCardView(state: runtime.consentState, question: consentQuestion,
                            onAnswer: { runtime.tapAnswer(yes: $0) }, onCancel: { runtime.cancelConsent() })
        }
        .fullScreenCover(isPresented: $previewConsentCard) {
            ConsentCardView(state: .listening, question: Phrasebook.consentQuestion(userName: state.userName, name: "Marcus"),
                            onAnswer: { _ in previewConsentCard = false }, onCancel: { previewConsentCard = false })
        }
        .sheet(isPresented: $showReadiness) { ReadinessView(onDone: { showReadiness = false; readinessDone = true }) }
        .onReceive(coordinator.$services) { services in
            if let services { runtime.bind(services: services, state: state, coordinator: coordinator) }
        }
        .onChange(of: runtime.lastSaved) { _, person in
            if let person { detailPerson = person; showDetail = true }
        }
        .onAppear { if !readinessDone { showReadiness = true } }
    }

    private func whoIsHere() { if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() } }
    private func rememberThem() { if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() } }

    private var consentQuestion: String {
        if case let .asking(name) = runtime.consentState { return Phrasebook.consentQuestion(userName: state.userName, name: name) }
        return Phrasebook.consentQuestion(userName: state.userName, name: runtime.nameGuess?.name)
    }

    // MARK: - Cards

    private var heroCard: some View {
        let services = coordinator.services
        let route = services?.audioInput.route.title ?? "–"
        let level = services?.audioInput.micLevel ?? 0
        let accent = state.muted ? FamiliarTheme.danger : FamiliarTheme.known
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.muted ? "Muted" : "Listening")
                    .font(.familiarHero)
                    .foregroundStyle(accent)
                    .contentTransition(.opacity)
                Spacer()
                MicMeter(level: level, color: accent)
            }
            Text("\(state.mode.title) mode · \(state.source.title) · \(route)")
                .font(.familiarBody)
                .foregroundStyle(.secondary)
            consentStatus
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(state.muted ? "muted" : "listening"), \(state.mode.title) mode, source \(state.source.title), audio \(route)")
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $state.mode) {
                ForEach(ChatterMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Chatter mode")
            .accessibilityHint("Quiet says less, chatty says more")
            .onChange(of: state.mode) { _, mode in coordinator.setMode(mode) }
            Toggle(isOn: $state.muted) {
                Label("Mute", systemImage: state.muted ? "speaker.slash" : "speaker.wave.2").font(.familiarBody.weight(.semibold))
            }
            .tint(FamiliarTheme.danger)
            .accessibilityHint("Stops all cues except urgent ones")
            .onChange(of: state.muted) { _, muted in coordinator.setMuted(muted) }
        }
        .padding(16)
        .glassCard()
    }

    private var sourceCard: some View {
        HStack {
            Label("Source", systemImage: "video").font(.familiarBody.weight(.semibold))
            Spacer()
            Picker("Source", selection: $state.source) {
                Text("Phone camera").tag(Services.Source.phone)
                Text("Glasses").tag(Services.Source.glasses)
                ForEach(VideoFileFrameSource.availableFixtures(), id: \.self) { name in
                    Text("Fixture: \(name)").tag(Services.Source.fixture(name))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Video source")
            .accessibilityHint("Phone camera, glasses, or a bundled test clip")
            .onChange(of: state.source) { _, source in Task { await coordinator.restart(source: source) } }
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder private var consentStatus: some View {
        switch runtime.consentState {
        case .idle: EmptyView()
        case .confirmingWithUser: Label("Say yes to start remembering", systemImage: "questionmark.bubble").foregroundStyle(.secondary)
        case .gathering: Label("Looking at them…", systemImage: "viewfinder").foregroundStyle(.secondary)
        case .asking, .listening, .saving: Label("Asking for permission…", systemImage: "waveform").foregroundStyle(FamiliarTheme.consent)
        case let .done(person): Label("Saved \(person.name)", systemImage: "checkmark.circle").foregroundStyle(FamiliarTheme.known)
        case .declined: Label("They said no. Nothing saved.", systemImage: "xmark.circle")
        case let .cancelled(reason): Label("Cancelled: \(reason)", systemImage: "xmark.circle")
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
