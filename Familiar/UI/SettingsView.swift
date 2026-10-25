import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var runtime: FlowRuntime
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage(UserSettings.voiceProvider) private var voiceProvider = "elevenlabs"
    @AppStorage(UserSettings.matchThreshold) private var matchThreshold = 0.40
    @AppStorage(UserSettings.audioRoute) private var audioRoute = "auto"
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "askPoyo"
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @AppStorage(UserSettings.assistantBrain) private var assistantBrain = "vision"
    @AppStorage(UserSettings.streamingTTS) private var streamingTTS = true
    @State private var confirmReset = false
    @State private var calibrating = false
    @State private var calibration: String?

    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $state.userName).accessibilityHint("Said in the consent question")
                TextField("Place name (optional)", text: $state.placeName).accessibilityHint("Overrides the location name saved with each person")
                Button { calibrate() } label: { Label(calibrating ? "Listening… keep talking" : "Calibrate my voice", systemImage: "waveform") }
                    .disabled(calibrating || coordinator.services?.vad == nil)
                    .accessibilityHint("Talk normally for three seconds so the app can tell your voice from other people's")
                if let calibration { Text(calibration).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Voice") {
                Picker("Voice", selection: $voiceProvider) {
                    Text("ElevenLabs").tag("elevenlabs"); Text("Apple").tag("apple")
                }
                .accessibilityHint("ElevenLabs falls back to the Apple voice when slow")
                Toggle("Stream speech (faster)", isOn: $streamingTTS)
                    .accessibilityHint("Plays each answer as it is synthesized instead of waiting for the whole clip. Turn off if speech stutters.")
                    .onChange(of: streamingTTS) { _, on in (coordinator.services?.speaker as? VoiceSpeaker)?.streaming = on }
                Picker("Audio route", selection: $audioRoute) {
                    Text("Automatic").tag("auto"); Text("Phone mic + glasses").tag("phoneMicGlassesA2DP"); Text("Glasses HFP").tag("glassesHFP"); Text("Phone only").tag("phoneOnly")
                }
                .accessibilityHint("Where the microphone and speaker are. Glasses HFP stops the glasses camera.")
                .onChange(of: audioRoute) { _, _ in Task { await coordinator.restart(source: state.source) } }
                Picker("Volume button", selection: $volumePrimary) {
                    Text("Ask Poyo (click, then talk)").tag("askPoyo"); Text("Who's here?").tag("whoIsHere"); Text("Remember them").tag("rememberThem")
                }
                .accessibilityHint("What a volume button press triggers")
                Toggle("Speak cues aloud (Simulator)", isOn: $state.speakLogSpeakerAloud)
                    .accessibilityHint("Uses the Apple voice for the logged speaker")
            }
            Section("Assistant") {
                Picker("Poyo runs on", selection: $assistantBrain) {
                    Text("Vision model (sees the view)").tag("vision"); Text("ElevenLabs agent (text only)").tag("elevenlabs")
                }
                .accessibilityHint("The vision model gets camera frames with every face blacked out. The ElevenLabs agent gets text only.")
                .onChange(of: assistantBrain) { _, _ in Task { await coordinator.restart(source: state.source) } }
            }
            Section("Recognition") {
                VStack(alignment: .leading) {
                    Text("Match threshold \(matchThreshold, specifier: "%.2f")")
                    Slider(value: $matchThreshold, in: 0.25...0.60, step: 0.01)
                        .accessibilityLabel("Match threshold")
                        .accessibilityValue(String(format: "%.2f", matchThreshold))
                        .accessibilityHint("Higher means fewer false names")
                }
            }
            Section("Keys") {
                row("ElevenLabs key", Secrets.elevenLabsAPIKey != nil)
                row("ElevenLabs agent", Secrets.elevenLabsAgentID != nil)
                row("Meta Model API key", Secrets.metaModelAPIKey != nil)
                row("Vision model", coordinator.services?.cloudScene.isConfigured ?? false)
                row("Modal endpoint", Secrets.modalEmbedURL != nil)
                LabeledContent("Name extractor", value: runtime.metaClient == nil ? "regex" : "regex → Apple → Meta")
            }
            Section("Privacy") {
                Text(JudgeView.banner).font(.footnote)
                Text("Removing a person deletes their record, thumbnail, consent clip and the contact this app created.").font(.footnote).foregroundStyle(.secondary)
                Button(role: .destructive) { confirmReset = true } label: { Label("Remove everyone", systemImage: "trash") }
                    .accessibilityHint("Deletes every remembered person and their files")
                Button("Show readiness check again") { readinessDone = false }
                    .accessibilityHint("The checklist appears next time you open the home screen")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove everyone?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remove everyone", role: .destructive) { runtime.resetPeople() }
            Button("Keep", role: .cancel) {}
        }
    }

    private func calibrate() {
        guard let vad = coordinator.services?.vad else { return }
        calibrating = true
        Task {
            await vad.calibrateUser(seconds: 3)
            if vad.isCalibrated {
                UserDefaults.standard.set(vad.userRMS, forKey: UserSettings.userVoiceRMS)
                calibration = "Calibrated to your voice."
            } else {
                calibration = "I didn't hear you. Try again."
            }
            calibrating = false
        }
    }

    private func row(_ title: String, _ ok: Bool) -> some View {
        HStack { Text(title); Spacer(); Label(ok ? "present" : "missing", systemImage: ok ? "checkmark.circle" : "xmark.circle").foregroundStyle(ok ? .green : .secondary) }
            .accessibilityElement(children: .combine)
    }
}
