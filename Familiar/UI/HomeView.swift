import SwiftUI

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
    @State private var selfEnroll: SelfEnrollModel?
    @StateObject private var nfc = NFCTagReader()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusLine
                    // Voice commands also change mode and mute and speak for themselves; only a tap here should speak.
                    Picker("Mode", selection: Binding(get: { state.mode }, set: { state.mode = $0; coordinator.setMode($0) })) {
                        ForEach(ChatterMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Chatter mode")
                    .accessibilityHint("Quiet says less, chatty says more")
                    Toggle("Mute", isOn: Binding(get: { state.muted }, set: { state.muted = $0; coordinator.setMuted($0) }))
                        .accessibilityHint("Stops all cues except urgent ones")
                }
                Section {
                    Button { whoIsHere() } label: { Label("Who's here?", systemImage: "person.2.wave.2") }
                        .font(.title3.weight(.semibold))
                        .accessibilityHint("Lists the known people around you, then counts the others")
                    Button { rememberThem() } label: { Label("Remember them", systemImage: "person.badge.plus") }
                        .font(.title3.weight(.semibold))
                        .disabled(runtime.showsConsentCard)
                        .accessibilityHint("Asks the person in front of you for permission to remember their face")
                    consentStatus
                }
                Section {
                    Button { introduce() } label: {
                        Label("Introduce yourself", systemImage: "person.crop.circle.badge.plus")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.services == nil || runtime.showsConsentCard)
                    .accessibilityLabel("Introduce yourself")
                    .accessibilityHint("Hand the phone to the person in front of you. They scan their face, type their name and tap yes themselves")
                    if NFCTagReader.isAvailable {
                        Button { nfc.scan { url in coordinator.handle(url: url) } } label: { Label("Scan tag", systemImage: "wave.3.right.circle") }
                            .disabled(nfc.isScanning)
                            .accessibilityHint("Hold the phone near an NFC tag that opens the introduce screen")
                    }
                    if let st = nfc.status { Text(st).font(.footnote).foregroundStyle(.secondary).accessibilityLabel("Tag: \(st)") }
                } footer: {
                    Text("Anyone can introduce themselves on this phone, or tap an NFC tag that opens familiar://introduce.")
                }
                Section("Source") {
                    Picker("Source", selection: $state.source) {
                        Text("Phone camera").tag(Services.Source.phone)
                        Text("Glasses").tag(Services.Source.glasses)
                        ForEach(VideoFileFrameSource.availableFixtures(), id: \.self) { name in
                            Text("Fixture: \(name)").tag(Services.Source.fixture(name))
                        }
                    }
                    .accessibilityLabel("Video source")
                    .accessibilityHint("Phone camera, glasses, or a bundled test clip")
                    .onChange(of: state.source) { _, new in Task { await coordinator.restart(source: new) } }
                    NavigationLink {
                        // Share the live source: the glasses accept one DAT session at a time.
                        GlassesRegistrationView(source: coordinator.services?.frameSource as? GlassesFrameSource)
                            .onDisappear { coordinator.ensureGlasses() }
                    } label: { Label("Connect glasses", systemImage: "eyeglasses") }
                        .accessibilityHint("Approve this app in Meta AI and allow the glasses camera")
                }
                Section {
                    NavigationLink { JudgeView().environmentObject(runtime) } label: { Label("Judge view", systemImage: "eye") }
                        .accessibilityHint("Shows the camera preview, cues and the event log")
                    NavigationLink { PeopleView().environmentObject(runtime) } label: {
                        HStack { Label("People", systemImage: "person.crop.rectangle.stack"); Spacer(); Text("\(runtime.people.count)").foregroundStyle(.secondary) }
                    }
                    .accessibilityLabel("People, \(runtime.people.count) remembered")
                    .accessibilityHint("Everyone who agreed to be remembered")
                    NavigationLink { SettingsView().environmentObject(runtime) } label: { Label("Settings", systemImage: "gear") }
                        .accessibilityHint("Your name, voice, thresholds and keys")
                    NavigationLink { DemoControlsView().environmentObject(runtime) } label: { Label("Demo controls", systemImage: "wand.and.stars") }
                        .accessibilityHint("Scripted demo helpers for the Simulator")
                    Button { showReadiness = true } label: { Label("Readiness check", systemImage: "checklist") }
                        .accessibilityHint("Checks permissions, model and keys")
                }
                if let err = coordinator.lastError {
                    Section("Last error") { Text(err).foregroundStyle(.red).accessibilityLabel("Last error: \(err)") }
                }
            }
            .navigationTitle("Familiar")
            .navigationDestination(isPresented: $showDetail) { if let p = detailPerson { PersonDetailView(person: p).environmentObject(runtime) } }
        }
        .background(VolumeButtonObserver { pressed in
            guard pressed else { return }
            if volumePrimary == "rememberThem" { rememberThem() } else { whoIsHere() }
        })
        .fullScreenCover(isPresented: Binding(get: { runtime.showsConsentCard }, set: { if !$0 { runtime.cancelConsent() } })) {
            ConsentCardView(state: runtime.consentState, question: consentQuestion, onAnswer: { runtime.tapAnswer(yes: $0) }, onCancel: { runtime.cancelConsent() })
        }
        .fullScreenCover(isPresented: $previewConsentCard) {
            ConsentCardView(state: .listening, question: Phrasebook.consentQuestion(userName: state.userName, name: "Marcus"), onAnswer: { _ in previewConsentCard = false }, onCancel: { previewConsentCard = false })
        }
        .sheet(isPresented: $showReadiness) { ReadinessView(onDone: { showReadiness = false; readinessDone = true }) }
        .fullScreenCover(item: $selfEnroll) { model in
            SelfEnrollView(model: model, onClose: { selfEnroll = nil })
                .interactiveDismissDisabled()
        }
        .onChange(of: coordinator.pendingRoute) { _, route in
            guard let route else { return }
            coordinator.pendingRoute = nil
            if route == .introduce { introduce() }
        }
        .onChange(of: selfEnroll?.step) { _, step in
            if case let .done(p)? = step { runtime.refreshPeople(); _ = p }
        }
        .onReceive(coordinator.$services) { s in if let s { runtime.bind(services: s, state: state, coordinator: coordinator) } }
        .onChange(of: runtime.lastSaved) { _, p in if let p { detailPerson = p; showDetail = true } }
        .onAppear { if !readinessDone { showReadiness = true } }
    }

    private func whoIsHere() { if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() } }
    private func introduce() {
        guard selfEnroll == nil, let s = coordinator.services else { return }
        if runtime.showsConsentCard { runtime.cancelConsent() }
        selfEnroll = SelfEnrollFactory.make(services: s, runtime: runtime, state: state)
    }
    private func rememberThem() { if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() } }

    private var consentQuestion: String {
        if case let .asking(name) = runtime.consentState { return Phrasebook.consentQuestion(userName: state.userName, name: name) }
        if let q = (runtime.consentFlow as? SpokenConsentFlow)?.lastQuestion { return q }
        return Phrasebook.consentQuestion(userName: state.userName, name: runtime.nameGuess?.name)
    }

    @ViewBuilder private var consentStatus: some View {
        switch runtime.consentState {
        case .idle: EmptyView()
        case .confirmingWithUser: Label("Say yes to start remembering", systemImage: "questionmark.bubble").foregroundStyle(.secondary)
        case .gathering: Label("Looking at them…", systemImage: "viewfinder").foregroundStyle(.secondary)
        case .asking, .listening, .saving: Label("Asking for permission…", systemImage: "waveform").foregroundStyle(.secondary)
        case let .done(p): Label("Saved \(p.name)", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .declined: Label("They said no. Nothing saved.", systemImage: "xmark.circle")
        case let .cancelled(r): Label("Cancelled: \(r)", systemImage: "xmark.circle")
        }
    }

    private var statusLine: some View {
        let s = coordinator.services
        let route = s?.audioInput.route.title ?? "–"
        let level = Int(((s?.audioInput.micLevel ?? 0) * 4).rounded())
        let bars = String(repeating: "▮", count: level) + String(repeating: "▯", count: max(0, 4 - level))
        return Text("\(state.mode.title) · \(route) · \(state.source.title) · mic \(bars)")
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Status: \(state.mode.title) mode, audio \(route), source \(state.source.title)")
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
