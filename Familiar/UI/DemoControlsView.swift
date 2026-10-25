import SwiftUI

/// Table-side helpers for the demo. Everything here is also reachable by voice or the Home buttons.
struct DemoControlsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @AppStorage(UserSettings.autoReplyInSimulator) private var autoReply = false
    @AppStorage(UserSettings.selfEnrollUseFixture) private var selfEnrollUseFixture = SelfEnrollFactory.useFixtureDefault
    @State private var customReply = ""
    @State private var confirmReset = false
    @State private var prewarmStatus: String?
    @State private var showStats = true

    var body: some View {
        Form {
            Section("Script") {
                Button { Task { await coordinator.restart(source: .fixture("conversation")) } } label: { Label("Run the demo script (conversation fixture)", systemImage: "play.rectangle") }
                    .accessibilityHint("Restarts perception on the scripted 29 second clip")
                Picker("Fixture", selection: $state.source) {
                    ForEach(VideoFileFrameSource.availableFixtures(), id: \.self) { Text($0).tag(Services.Source.fixture($0)) }
                }
                .accessibilityHint("Pick another bundled clip")
                .onChange(of: state.source) { _, new in Task { await coordinator.restart(source: new) } }
            }
            Section("Consent") {
                Button { runtime.rememberThem() } label: { Label("Force the consent flow now", systemImage: "person.badge.plus") }
                    .disabled(runtime.showsConsentCard)
                    .accessibilityHint("Skips the goodbye detector and asks the closest stranger")
                Button { runtime.send(.cancel) } label: { Label("Cancel consent", systemImage: "xmark.circle") }
                    .accessibilityHint("Stops any flow in progress")
                if runtime.hasFakeTranscriber {
                    Button { runtime.fakeReply("Yes, sure.") } label: { Label("Other person says “Yes, sure.”", systemImage: "hand.thumbsup") }
                        .accessibilityHint("Injects a spoken yes into the fake transcriber")
                    Button { runtime.fakeReply("Nah, I'm good.") } label: { Label("Other person says “Nah, I'm good.”", systemImage: "hand.thumbsdown") }
                        .accessibilityHint("Injects a spoken no")
                    Button { runtime.fakeReply("Hey, hi! I'm Marcus.") } label: { Label("Other person says “I'm Marcus.”", systemImage: "person.wave.2") }
                        .accessibilityHint("Gives the name extractor something to find")
                    HStack {
                        TextField("Custom line as the other person", text: $customReply).accessibilityHint("Injected as a final transcript segment")
                        Button("Send") { runtime.fakeReply(customReply); customReply = "" }.disabled(customReply.isEmpty)
                            .accessibilityLabel("Send custom line")
                    }
                }
                LabeledContent("Consent state", value: consentLabel)
                LabeledContent("Name guess", value: runtime.nameGuess?.name.map { "\($0) (\(runtime.nameGuess?.source ?? ""), \(String(format: "%.1f", runtime.nameGuess?.confidence ?? 0)))" } ?? "none")
            }
            Section("Introduce yourself") {
                Toggle("Use the enroll_marcus clip instead of the front camera", isOn: $selfEnrollUseFixture)
                    .accessibilityHint("On in the Simulator, which has no camera")
                Button { coordinator.handle(url: URL(string: "familiar://introduce")!) } label: { Label("Simulate the NFC tag (familiar://introduce)", systemImage: "wave.3.right.circle") }
                    .accessibilityHint("Opens the introduce screen the way a tag would")
            }
            Section("Voice") {
                Button { prewarm() } label: { Label("Re-prewarm phrases", systemImage: "flame") }
                    .accessibilityHint("Synthesizes the consent phrases again so the question plays instantly")
                if let prewarmStatus { Text(prewarmStatus).font(.footnote).foregroundStyle(.secondary) }
                Button { runtime.send(.repeatLast) } label: { Label("Repeat last", systemImage: "arrow.counterclockwise") }
                    .accessibilityHint("Says the last cue again")
                Button { coordinator.services?.speaker.stopAll() } label: { Label("Stop speaking", systemImage: "speaker.slash") }
                    .accessibilityHint("Interrupts the voice")
            }
            Section("Stats") {
                Toggle("Show FPS and latency", isOn: $showStats).accessibilityHint("Shows live numbers below")
                if showStats {
                    LabeledContent("FPS", value: String(format: "%.0f", coordinator.fps))
                    LabeledContent("Tracks", value: "\(coordinator.tracks.count)")
                    LabeledContent("Last cue latency", value: lastLatency)
                    LabeledContent("Audio route", value: coordinator.services?.audioInput.route.title ?? "–")
                    LabeledContent("Mic level", value: String(format: "%.2f", coordinator.services?.audioInput.micLevel ?? 0))
                }
            }
            Section("Memory") {
                LabeledContent("People", value: "\(runtime.people.count)")
                LabeledContent("Store", value: runtime.isBridged ? "JSONPeopleStore (UI-bridged)" : "Services.peopleStore")
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset people", systemImage: "trash") }
                    .accessibilityHint("Deletes everyone and their files. Keeps the voice cache")
            }
        }
        .navigationTitle("Demo controls")
        .confirmationDialog("Delete every remembered person?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset people", role: .destructive) { runtime.resetPeople() }
            Button("Keep", role: .cancel) {}
        }
    }

    private func prewarm() {
        prewarmStatus = "Prewarming…"
        let name = state.userName
        Task {
            let phrases = [Phrasebook.shouldIAdd, Phrasebook.scanningFace, Phrasebook.lookTowardMe, Phrasebook.consentQuestion(userName: name, name: runtime.nameGuess?.name), Phrasebook.consentQuestion(userName: name, name: nil), Phrasebook.wasThatAYes, Phrasebook.whatShouldICallYou, Phrasebook.nothingSaved, Phrasebook.theyLeft]
            await coordinator.services?.speaker.prewarm(phrases)
            prewarmStatus = "Prewarmed \(phrases.count) phrases"
        }
    }

    private var lastLatency: String {
        guard let e = coordinator.utterances.last, let w = e.window else { return "–" }
        return String(format: "%.0f ms", (w.lowerBound - e.at) * 1000)
    }

    private var consentLabel: String { ConsentStateLabel.text(runtime.consentState) }
}

enum ConsentStateLabel {
    static func text(_ s: ConsentState) -> String {
        switch s {
        case .idle: return "idle"
        case .confirmingWithUser: return "confirming with user"
        case let .gathering(t): return "gathering (track \(t))"
        case let .asking(n): return "asking \(n ?? "someone")"
        case .listening: return "listening"
        case .saving: return "saving"
        case let .done(p): return "done: \(p.name)"
        case .declined: return "declined"
        case let .cancelled(r): return "cancelled: \(r)"
        }
    }
}
