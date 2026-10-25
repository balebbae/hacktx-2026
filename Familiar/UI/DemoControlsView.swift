import SwiftUI

/// Table-side helpers for the demo. Everything here is also reachable by voice or from Today; nothing is pretend.
struct DemoControlsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.visionScale) private var scale
    @State private var customReply = ""
    @State private var confirmReset = false
    @State private var prewarmStatus: String?
    @State private var showStats = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                scriptSection
                consentSection
                voiceSection
                statsSection
                memorySection
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .youNavigationTitle("Demo controls")
        .confirmationDialog(YouCopy.removeEveryoneTitle(runtime.people.count), isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remove \(YouCopy.people(runtime.people.count))", role: .destructive) { resetPeople() }
            Button("Keep everyone", role: .cancel) {}
        } message: {
            Text("Deletes every record, face sample, thumbnail, consent clip and the contacts this app created. The voice cache is kept.")
        }
    }

    // MARK: - Sections

    private var intro: some View {
        Text("Scripted helpers for the table. Everything here is also reachable by voice or from Today.")
            .font(FamiliarType.supporting(scale))
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .padding(.horizontal, 4)
    }

    private var scriptSection: some View {
        YouSection(title: "Script", footer: "Restarting perception replays the chosen clip from the start.") {
            YouActionRow(title: "Run the demo script",
                         systemImage: "play.rectangle",
                         detail: "Conversation fixture, 29 seconds",
                         hint: "Restarts perception on the scripted clip") {
                Task { await coordinator.restart(source: .fixture("conversation")) }
            }
            YouDivider()
            YouChoiceRow(title: "Fixture", detail: "Pick another bundled clip") {
                fixturePicker
            }
        }
    }

    private var fixturePicker: some View {
        Picker("Fixture", selection: $state.source) {
            ForEach(VideoFileFrameSource.availableFixtures(), id: \.self) { (name: String) in
                Text(name).tag(Services.Source.fixture(name))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(FamiliarPalette.ink(scale))
        .font(FamiliarType.body(scale))
        .frame(minHeight: scale.hitTarget, alignment: .leading)
        .accessibilityHint("Pick another bundled clip")
        .onChange(of: state.source) { _, new in Task { await coordinator.restart(source: new) } }
    }

    private var consentSection: some View {
        YouSection(title: "Consent") {
            YouActionRow(title: "Force the consent flow now",
                         systemImage: "person.badge.plus",
                         detail: "Skips the goodbye detector and asks the closest stranger",
                         hint: "Starts asking right away") { runtime.rememberThem() }
                .disabled(runtime.showsConsentCard)
            YouDivider()
            YouActionRow(title: "Cancel consent",
                         systemImage: "xmark.circle",
                         detail: "Stops any flow in progress") { runtime.send(.cancel) }
            if runtime.hasFakeTranscriber {
                YouDivider()
                fakeReplies
            }
            YouDivider()
            YouValueRow(title: "Consent state", value: consentLabel, systemImage: "hand.raised")
            YouDivider()
            YouValueRow(title: "Name guess", value: nameGuessLabel, systemImage: "text.magnifyingglass")
        }
    }

    /// Simulator only: lines injected into the fake transcriber as the other person.
    private var fakeReplies: some View {
        VStack(spacing: 0) {
            YouActionRow(title: "Other person says “Yes, sure.”",
                         systemImage: "hand.thumbsup",
                         hint: "Injects a spoken yes into the fake transcriber") { runtime.fakeReply("Yes, sure.") }
            YouDivider()
            YouActionRow(title: "Other person says “Nah, I'm good.”",
                         systemImage: "hand.thumbsdown",
                         hint: "Injects a spoken no") { runtime.fakeReply("Nah, I'm good.") }
            YouDivider()
            YouActionRow(title: "Other person says “I'm Marcus.”",
                         systemImage: "person.wave.2",
                         hint: "Gives the name extractor something to find") { runtime.fakeReply("Hey, hi! I'm Marcus.") }
            YouDivider()
            customLine
        }
    }

    private var customLine: some View {
        HStack(spacing: 10) {
            TextField("Custom line as the other person", text: $customReply)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .textFieldStyle(.plain)
                .accessibilityHint("Injected as a final transcript segment")
            Button("Send") { runtime.fakeReply(customReply); customReply = "" }
                .buttonStyle(GhostPillStyle())
                .frame(width: 96 * scale.textScale)
                .disabled(customReply.isEmpty)
                .accessibilityLabel("Send custom line")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: scale.hitTarget)
    }

    private var voiceSection: some View {
        YouSection(title: "Voice", footer: prewarmStatus) {
            YouActionRow(title: "Re-prewarm phrases",
                         systemImage: "flame",
                         detail: "Synthesizes the consent phrases again so the question plays instantly") { prewarm() }
            YouDivider()
            YouActionRow(title: "Repeat last",
                         systemImage: "arrow.counterclockwise",
                         detail: "Says the last cue again") { runtime.send(.repeatLast) }
            YouDivider()
            YouActionRow(title: "Stop speaking",
                         systemImage: "speaker.slash",
                         detail: "Interrupts the voice") { coordinator.services?.speaker.stopAll() }
        }
    }

    private var statsSection: some View {
        YouSection(title: "Stats") {
            YouToggleRow(title: "Show FPS and latency", systemImage: "speedometer", isOn: $showStats, hint: "Shows live numbers below")
            if showStats {
                YouDivider()
                statsRows
            }
        }
    }

    private var statsRows: some View {
        VStack(spacing: 0) {
            YouValueRow(title: "FPS", value: String(format: "%.0f", coordinator.fps))
            YouDivider(inset: YouMetrics.plainInset)
            countRow("Tracks", coordinator.tracks.count)
            YouDivider(inset: YouMetrics.plainInset)
            YouValueRow(title: "Last cue latency", value: lastLatency)
            YouDivider(inset: YouMetrics.plainInset)
            YouValueRow(title: "Audio route", value: coordinator.services?.audioInput.route.title ?? "–")
            YouDivider(inset: YouMetrics.plainInset)
            YouValueRow(title: "Mic level", value: String(format: "%.2f", coordinator.services?.audioInput.micLevel ?? 0))
        }
    }

    private var memorySection: some View {
        YouSection(title: "Memory") {
            countRow("People", runtime.people.count)
            YouDivider(inset: YouMetrics.plainInset)
            YouValueRow(title: "Store", value: runtime.isBridged ? "JSONPeopleStore (UI-bridged)" : "Services.peopleStore")
            YouDivider(inset: YouMetrics.plainInset)
            YouActionRow(title: "Remove everyone",
                         systemImage: "trash",
                         detail: "Deletes everyone and their files. Keeps the voice cache",
                         role: .destructive,
                         hint: "Asks before deleting \(YouCopy.people(runtime.people.count))") { confirmReset = true }
                .disabled(runtime.people.isEmpty)
        }
    }

    /// A row whose number pops in when it changes.
    private func countRow(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
            Spacer(minLength: 12)
            NumberPop(value: value, font: FamiliarType.title(scale), color: FamiliarPalette.ink(scale))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: scale.hitTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Actions and facts

    private func resetPeople() {
        runtime.resetPeople()
        FamiliarHaptics.play(.paused)
    }

    private func prewarm() {
        prewarmStatus = "Prewarming…"
        let name = state.userName
        Task {
            let phrases = [Phrasebook.wantToRemember, Phrasebook.lookTowardMe, Phrasebook.consentQuestion(userName: name, name: runtime.nameGuess?.name), Phrasebook.consentQuestion(userName: name, name: nil), Phrasebook.wasThatAYes, Phrasebook.whatShouldICallYou, Phrasebook.nothingSaved, Phrasebook.theyLeft]
            await coordinator.services?.speaker.prewarm(phrases)
            prewarmStatus = "Prewarmed \(phrases.count) phrases"
        }
    }

    private var lastLatency: String {
        guard let e = coordinator.utterances.last, let w = e.window else { return "–" }
        return String(format: "%.0f ms", (w.lowerBound - e.at) * 1000)
    }

    private var consentLabel: String { ConsentStateLabel.text(runtime.consentState) }

    private var nameGuessLabel: String {
        guard let guess = runtime.nameGuess, let name = guess.name else { return "none" }
        return "\(name) (\(guess.source), \(String(format: "%.1f", guess.confidence)))"
    }
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

#Preview("Demo controls") {
    NavigationStack {
        DemoControlsView()
            .environmentObject(AppState())
            .environmentObject(AppCoordinator())
            .environmentObject(FlowRuntime())
    }
}
