import SwiftUI

/// Voice and cues: the same settings and UserDefaults keys as before, laid out on the canvas as white sections.
/// Removing everyone lives in the privacy dashboard (one confirmation that names the count); this screen links to it.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var runtime: FlowRuntime
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.visionScale) private var scale
    @AppStorage(UserSettings.voiceProvider) private var voiceProvider = "elevenlabs"
    @AppStorage(UserSettings.matchThreshold) private var matchThreshold = 0.40
    @AppStorage(UserSettings.audioRoute) private var audioRoute = "auto"
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "askPoyo"
    /// Default on: the cue policy has always said "Marcus." when a known person starts talking (`SpeechPreferences`).
    @AppStorage(SpeechPreferences.speakingCueKey) private var cueSpeaking = true
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @AppStorage(UserSettings.assistantBrain) private var assistantBrain = "vision"
    @State private var calibrating = false
    @State private var calibration: String?

    private static let voiceOptions: [(String, String)] = [("elevenlabs", "ElevenLabs"), ("apple", "Apple")]
    /// "pauseCues" is the fixed mute action spec 20.4 asks for; `MainTabView` handles all three.
    private static let volumeOptions: [(String, String)] = [("askPoyo", "Ask Poyo"), ("whoIsHere", "Who's here"), ("rememberThem", "Remember"), ("pauseCues", "Pause")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                youSection
                voiceSection
                assistantSection
                recognitionSection
                cuesSection
                keysSection
                PrivacyBanner(text: JudgeView.banner)
                privacySection
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .youNavigationTitle("Voice and cues")
    }

    // MARK: - Sections

    private var intro: some View {
        Text("How Familiar speaks, what it says, and how sure it has to be before it says a name.")
            .font(FamiliarType.supporting(scale))
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .padding(.horizontal, 4)
    }

    private var youSection: some View {
        YouSection(title: "You") {
            YouTextFieldRow(title: "Your name", text: $state.userName, placeholder: "Add your name", hint: "Said in the consent question")
            YouDivider(inset: YouMetrics.plainInset)
            YouTextFieldRow(title: "Place name", text: $state.placeName, placeholder: "Optional", hint: "Overrides the location name saved with each person")
            YouDivider()
            YouActionRow(title: calibrating ? "Listening… keep talking" : "Calibrate my voice",
                         systemImage: "waveform",
                         detail: calibration ?? "Talk normally for three seconds so Familiar can tell your voice from other people's",
                         hint: "Talk normally for three seconds so the app can tell your voice from other people's") { calibrate() }
                .disabled(calibrating || coordinator.services?.vad == nil)
        }
    }

    private var voiceSection: some View {
        YouSection(title: "Voice") {
            YouChoiceRow(title: "Voice", detail: "Which voice speaks the cues. ElevenLabs falls back to the Apple voice when slow") {
                SlidingPillSegment(options: Self.voiceOptions, selection: $voiceProvider, label: "Voice")
            }
            YouDivider(inset: YouMetrics.plainInset)
            YouChoiceRow(title: "Audio route", detail: "Where the microphone and speaker are. Glasses HFP stops the glasses camera") {
                audioRoutePicker
            }
            YouDivider(inset: YouMetrics.plainInset)
            YouChoiceRow(title: "Volume button", detail: "What a press of a volume button triggers. Ask Poyo: click, then talk") {
                SlidingPillSegment(options: Self.volumeOptions, selection: $volumePrimary, label: "Volume button")
            }
            YouDivider(inset: YouMetrics.plainInset)
            YouToggleRow(title: "Speak cues aloud (Simulator)",
                         detail: "Uses the Apple voice for the logged speaker",
                         systemImage: "speaker.wave.2",
                         isOn: $state.speakLogSpeakerAloud)
        }
    }

    private static let brainOptions: [(String, String)] = [("vision", "Vision model"), ("elevenlabs", "ElevenLabs agent")]

    private var assistantSection: some View {
        YouSection(title: "Assistant",
                   footer: "The vision model gets camera frames with every face blacked out. The ElevenLabs agent gets text only.") {
            YouChoiceRow(title: "Poyo runs on", detail: "Vision model sees the view. ElevenLabs agent is text only") {
                SlidingPillSegment(options: Self.brainOptions, selection: $assistantBrain, label: "Poyo runs on")
            }
        }
        .onChange(of: assistantBrain) { _, _ in Task { await coordinator.restart(source: state.source) } }
    }

    private var audioRoutePicker: some View {
        Picker("Audio route", selection: $audioRoute) {
            Text("Automatic").tag("auto")
            Text("Phone mic + glasses").tag("phoneMicGlassesA2DP")
            Text("Glasses HFP").tag("glassesHFP")
            Text("Phone only").tag("phoneOnly")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(FamiliarPalette.ink(scale))
        .font(FamiliarType.body(scale))
        .frame(minHeight: scale.hitTarget, alignment: .leading)
        .accessibilityHint("Where the microphone and speaker are. Glasses HFP stops the glasses camera.")
        .onChange(of: audioRoute) { _, _ in Task { await coordinator.restart(source: state.source) } }
    }

    private var recognitionSection: some View {
        YouSection(title: "Recognition", footer: "Mistaken identity is worse than no identity. When unsure, Familiar says \"someone\".") {
            YouSliderRow(title: "Match threshold",
                         value: $matchThreshold,
                         range: 0.25...0.60,
                         step: 0.01,
                         minimumLabel: "More names",
                         maximumLabel: "Fewer mistakes",
                         hint: "Higher means fewer false names")
        }
    }

    /// "Speaking first" is read by the cue policy on every event. Presence, approach and leaving are always on.
    private var cuesSection: some View {
        YouSection(title: "Cues", footer: "Presence, approach and leaving are always on. Hazards are said at once, even when paused.") {
            YouToggleRow(title: "Speaking first",
                         detail: "Says a known person's name, softly, when they start talking",
                         systemImage: "mouth",
                         isOn: $cueSpeaking,
                         hint: "Applies to the next person who starts talking")
        }
    }

    private var keysSection: some View {
        YouSection(title: "Keys", footer: "Keys come from Secrets.xcconfig. Nothing is typed in here.") {
            keyRow("ElevenLabs key", Secrets.elevenLabsAPIKey != nil)
            YouDivider()
            keyRow("ElevenLabs agent", Secrets.elevenLabsAgentID != nil)
            YouDivider()
            keyRow("Meta Model API key", Secrets.metaModelAPIKey != nil)
            YouDivider()
            keyRow("Vision model", coordinator.services?.cloudScene.isConfigured ?? false)
            YouDivider()
            keyRow("Modal endpoint", Secrets.modalEmbedURL != nil)
            YouDivider()
            YouValueRow(title: "Name extractor",
                        value: runtime.metaClient == nil ? "regex" : "regex → Apple → Meta",
                        systemImage: "text.magnifyingglass")
        }
    }

    private var privacySection: some View {
        YouSection(title: "Privacy", footer: "Removing a person deletes their record, thumbnail, consent clip and the contact this app created.") {
            NavigationLink {
                PrivacyDashboardView()
            } label: {
                YouRow(title: "Privacy",
                       systemImage: "lock.shield",
                       detail: "Your people. Your control. \(YouCopy.people(runtime.people.count)) remembered")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens the privacy dashboard, where everyone can be removed")
            YouDivider()
            YouActionRow(title: "Show readiness check again",
                         systemImage: "checklist",
                         detail: "The checklist appears next time you open the home screen",
                         hint: "Resets the first-launch checklist") { readinessDone = false }
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

    private func keyRow(_ title: String, _ ok: Bool) -> some View {
        YouValueRow(title: title,
                    value: ok ? "present" : "missing",
                    systemImage: ok ? "checkmark.circle" : "xmark.circle",
                    tint: ok ? FamiliarPalette.success : FamiliarPalette.inkSecondary(scale))
    }
}

#Preview("Voice and cues") {
    NavigationStack {
        SettingsView()
            .environmentObject(AppState())
            .environmentObject(FlowRuntime())
            .environmentObject(AppCoordinator())
    }
}
