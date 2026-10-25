import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusLine
                    Picker("Mode", selection: $state.mode) {
                        ForEach(ChatterMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Chatter mode")
                    .accessibilityHint("Quiet says less, chatty says more")
                    .onChange(of: state.mode) { _, new in coordinator.setMode(new) }
                    Toggle("Mute", isOn: $state.muted)
                        .accessibilityHint("Stops all cues except urgent ones")
                        .onChange(of: state.muted) { _, new in coordinator.setMuted(new) }
                }
                Section {
                    Button { coordinator.whoIsHere() } label: { Label("Who's here?", systemImage: "person.2.wave.2") }
                        .font(.title3.weight(.semibold))
                        .accessibilityHint("Lists the known people around you, then counts the others")
                    Button { coordinator.rememberThem() } label: { Label("Remember them", systemImage: "person.badge.plus") }
                        .font(.title3.weight(.semibold))
                        .accessibilityHint("Asks the person in front of you for permission to remember their face")
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
                    .onChange(of: state.source) { _, new in Task { await coordinator.restart(source: new) } }
                }
                Section {
                    NavigationLink { JudgeView() } label: { Label("Judge view", systemImage: "eye") }
                    NavigationLink { PeopleView() } label: { Label("People", systemImage: "person.crop.rectangle.stack") }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gear") }
                }
                if let err = coordinator.lastError {
                    Section("Last error") { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Familiar")
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
