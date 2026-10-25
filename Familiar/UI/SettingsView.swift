import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var runtime: FlowRuntime
    @AppStorage(UserSettings.voiceProvider) private var voiceProvider = "elevenlabs"
    @AppStorage(UserSettings.embeddingProvider) private var embeddingProvider = "ondevice"
    @AppStorage(UserSettings.matchThreshold) private var matchThreshold = 0.40
    @AppStorage(UserSettings.minFacePx) private var minFacePx = 40
    @AppStorage(UserSettings.audioRoute) private var audioRoute = "auto"
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "whoIsHere"
    @AppStorage(UserSettings.cueSpeaking) private var cueSpeaking = false
    @AppStorage(UserSettings.cueWave) private var cueWave = false
    @AppStorage(UserSettings.cueSmile) private var cueSmile = false
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $state.userName).accessibilityHint("Said in the consent question")
                TextField("Place name (optional)", text: $state.placeName).accessibilityHint("Overrides the location name saved with each person")
            }
            Section("Voice") {
                Picker("Voice", selection: $voiceProvider) {
                    Text("ElevenLabs").tag("elevenlabs"); Text("Apple").tag("apple")
                }
                .accessibilityHint("ElevenLabs falls back to the Apple voice when slow")
                Picker("Audio route", selection: $audioRoute) {
                    Text("Automatic").tag("auto"); Text("Phone mic + glasses").tag("phoneMicGlassesA2DP"); Text("Glasses HFP").tag("glassesHFP"); Text("Glasses stream mic").tag("glassesStreamMic"); Text("Phone only").tag("phoneOnly")
                }
                .accessibilityHint("Where the microphone and speaker are")
                Picker("Volume button", selection: $volumePrimary) {
                    Text("Who's here?").tag("whoIsHere"); Text("Remember them").tag("rememberThem")
                }
                .accessibilityHint("What a volume button press triggers")
                Toggle("Speak cues aloud (Simulator)", isOn: $state.speakLogSpeakerAloud)
                    .accessibilityHint("Uses the Apple voice for the logged speaker")
            }
            Section("Recognition") {
                Picker("Embeddings", selection: $embeddingProvider) {
                    Text("On device").tag("ondevice"); Text("Modal fallback").tag("modal")
                }
                .accessibilityHint("Modal sends 112 by 112 face crops to a server and discards them")
                VStack(alignment: .leading) {
                    Text("Match threshold \(matchThreshold, specifier: "%.2f")")
                    Slider(value: $matchThreshold, in: 0.25...0.60, step: 0.01)
                        .accessibilityLabel("Match threshold")
                        .accessibilityValue(String(format: "%.2f", matchThreshold))
                        .accessibilityHint("Higher means fewer false names")
                }
                Stepper("Minimum face size \(minFacePx) px", value: $minFacePx, in: 24...120, step: 4)
                    .accessibilityHint("Faces smaller than this are ignored")
            }
            Section("Cues") {
                Toggle("Speaking first", isOn: $cueSpeaking).accessibilityHint("Says a known person's name when they start talking")
                Toggle("Wave", isOn: $cueWave).accessibilityHint("Stretch feature")
                Toggle("Smile", isOn: $cueSmile).accessibilityHint("Stretch feature")
            }
            Section("Keys") {
                row("ElevenLabs key", Secrets.elevenLabsAPIKey != nil)
                row("Meta Model API key", Secrets.metaModelAPIKey != nil)
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

    private func row(_ title: String, _ ok: Bool) -> some View {
        HStack { Text(title); Spacer(); Label(ok ? "present" : "missing", systemImage: ok ? "checkmark.circle" : "xmark.circle").foregroundStyle(ok ? .green : .secondary) }
            .accessibilityElement(children: .combine)
    }
}
