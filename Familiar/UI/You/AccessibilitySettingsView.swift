import SwiftUI
import UIKit

/// How Familiar communicates: one vision preference (not a diagnosis) with a live preview, haptics, speech rate and
/// volume, and whether cue text stays on screen. "Preview my settings" plays one sample cue through every channel
/// — voice, text and haptic — without turning on the camera or the microphone.
struct AccessibilitySettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openURL) private var openURL
    @AppStorage(YouSettings.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(YouSettings.speechRate) private var speechRate = 1.0
    /// Default 1: a missing key means unity gain in `SpeechPreferences`, so the slider shows what is heard.
    @AppStorage(YouSettings.speechVolume) private var speechVolume = 1.0
    @AppStorage(YouSettings.cueTextStaysOnScreen) private var cueTextStaysOnScreen = false
    @AppStorage(YouSettings.mimoPresence) private var mimoPresence = MimoPresence.full.rawValue
    @State private var previewCount = 0
    @State private var previewText: String?
    @State private var previewProblem: String?
    @State private var shakeTrigger = 0

    private static let mimoOptions: [(String, String)] = MimoPresence.allCases.map { (p: MimoPresence) -> (String, String) in (p.rawValue, p.title) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                VisionProfilePicker(selection: $state.visionProfile)
                VisionPreviewCard(profile: state.visionProfile,
                                  previewText: previewText,
                                  previewCount: previewCount,
                                  problem: previewProblem,
                                  shakeTrigger: shakeTrigger,
                                  onPreview: previewSettings)
                feel
                speech
                read
                mimo
                system
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .youNavigationTitle("Accessibility")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How would you like Familiar to communicate?")
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
            Text("One preference, not a diagnosis. Everything resizes right away, and you can change it any time.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .padding(.horizontal, 4)
    }

    private var feel: some View {
        YouSection(title: "Feel") {
            YouToggleRow(title: "Haptics",
                         detail: "A soft tap with each cue, a firmer one when someone says yes",
                         systemImage: "hand.tap",
                         isOn: $hapticsEnabled,
                         hint: "Turns every vibration on or off")
        }
    }

    /// The sliders persist under `YouSettings.speechRate` / `speechVolume`; the voice reads them per utterance
    /// (`SpeechPreferences`: the Apple voice and the Simulator voice follow the rate directly, ElevenLabs within its
    /// 0.7–1.2× range; volume is a gain applied by the speaker). A line already in the ElevenLabs cache at another
    /// rate is fetched again at the new one, so a change is heard on the very next cue.
    private var speech: some View {
        YouSection(title: "Speech", footer: "Both apply to the next thing the voice says. ElevenLabs keeps the rate between 0.7× and 1.2×; the Apple voice follows it directly. Cues stay three to six words long whatever the rate.") {
            YouSliderRow(title: "Speech rate",
                         value: $speechRate,
                         range: 0.8...1.3,
                         step: 0.05,
                         format: { (v: Double) -> String in String(format: "%.2f×", v) },
                         minimumLabel: "Slower",
                         maximumLabel: "Faster",
                         hint: "How fast the voice speaks, from the next cue on")
            YouDivider(inset: YouMetrics.plainInset)
            YouSliderRow(title: "Speech volume",
                         value: $speechVolume,
                         range: 0.3...1,
                         step: 0.05,
                         format: { (v: Double) -> String in "\(Int((v * 100).rounded()))%" },
                         minimumLabel: "Softer",
                         maximumLabel: "Louder",
                         hint: "How loud the voice is, within the phone volume, from the next cue on")
        }
    }

    /// Spec 19.6 Settings: Mimo visibility (full, compact, hidden) while the voice and the cue text stay the same.
    private var mimo: some View {
        YouSection(title: "Mimo", footer: "Mimo is the face of the app, never its voice. Cues are spoken and shown as text whatever you choose here.") {
            YouChoiceRow(title: "Mimo on Today and Room", detail: "The full stage, a small companion, or no Mimo at all") {
                SlidingPillSegment(options: Self.mimoOptions, selection: $mimoPresence, label: "Mimo visibility")
            }
        }
    }

    private var read: some View {
        YouSection(title: "Read", footer: "Every spoken cue also appears as text at the top of the screen.") {
            YouToggleRow(title: "Keep cue text on screen",
                         detail: "The last cue stays until the next one, instead of fading after five seconds",
                         systemImage: "text.bubble",
                         isOn: $cueTextStaysOnScreen,
                         hint: "For reading cues at your own pace")
        }
    }

    private var system: some View {
        YouSection(title: "From iOS", footer: systemFooter) {
            YouValueRow(title: "VoiceOver", value: onOff(voiceOverEnabled), systemImage: "speaker.wave.3")
            YouDivider()
            YouValueRow(title: "Reduce Motion", value: onOff(reduceMotion), systemImage: "slowmo")
            YouDivider()
            YouValueRow(title: "Increase Contrast", value: onOff(colorSchemeContrast == .increased), systemImage: "circle.lefthalf.filled")
            YouDivider()
            YouValueRow(title: "Differentiate Without Color", value: onOff(differentiateWithoutColor), systemImage: "paintpalette")
            YouDivider()
            YouActionRow(title: "Open iOS Settings",
                         systemImage: "gear",
                         detail: "Text size, VoiceOver, motion and contrast live there",
                         hint: "Leaves the app and opens Settings") { openSystemSettings() }
        }
    }

    private var systemFooter: String {
        if scale.spokenFirst {
            return "Non-visual: VoiceOver summaries come first and visuals stay simple. iOS settings always win."
        }
        return "iOS settings always win: Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast and Differentiate Without Color are respected on every screen."
    }

    private func onOff(_ on: Bool) -> String { on ? "On" : "Off" }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    // MARK: - Preview

    /// One sample cue through every channel: the speaker, the text toast and the cue haptic. No dedupe key, so every
    /// tap is audible (the toast and the haptic fire per tap too).
    private func previewSettings() {
        let text = Phrasebook.appeared(name: "Maya", bearing: .atClock(2), distance: .close)
        previewText = text
        previewCount += 1
        FamiliarHaptics.play(.cue)
        let speaker: (any Speaker)? = runtime.services?.speaker ?? coordinator.services?.speaker
        guard let speaker else {
            previewProblem = "The voice isn't ready yet. The text and the haptic still played."
            shakeTrigger += 1
            return
        }
        previewProblem = nil
        let utterance = Utterance(text: text, priority: 1, category: "preview", personID: nil, dedupeKey: nil, audience: .user, earcon: true)
        Task { await speaker.speak(utterance) }
    }
}

// MARK: - Vision profile picker

/// Four option cards, one selected. Each shows its name, what it changes, and an "Aa" at that profile's text size.
/// The change is animated only when motion is allowed now and by the profile being chosen.
struct VisionProfilePicker: View {
    @Binding var selection: VisionProfile
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ForEach(VisionProfile.allCases) { (profile: VisionProfile) in
                VisionProfileOption(profile: profile, isSelected: profile == selection) {
                    select(profile)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vision profile")
    }

    private func select(_ profile: VisionProfile) {
        guard profile != selection else { return }
        let animates: Bool = FamiliarMotion.animates(scale, reduceMotion: reduceMotion) && !VisionScale.make(profile).simplifyMotion
        withAnimation(FamiliarMotion.reduced(animates)) { selection = profile }
        FamiliarHaptics.play(.accepted)
    }
}

private struct VisionProfileOption: View {
    let profile: VisionProfile
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.visionScale) private var scale

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: FamiliarPalette.controlRadius + 4, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .visionIcon(scale, base: 22)
                    .foregroundStyle(isSelected ? FamiliarPalette.ocean(scale) : FamiliarPalette.inkSecondary(scale))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.title)
                        .font(FamiliarType.body(scale))
                        .foregroundStyle(FamiliarPalette.ink(scale))
                    Text(profile.detail)
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("Aa")
                    .font(sampleFont)
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: scale.hitTarget, alignment: .leading)
            .background(FamiliarPalette.surface(scale), in: shape)
            .overlay(shape.strokeBorder(isSelected ? FamiliarPalette.ocean(scale) : FamiliarPalette.stroke(scale),
                                        lineWidth: isSelected ? 2 : scale.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(VisionOptionButtonStyle())
        .accessibilityLabel("\(profile.title). \(profile.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Sets text size, icon size, contrast and motion for the whole app")
    }

    /// "Aa" at the size and weight this profile would give body text.
    private var sampleFont: Font {
        let s = VisionScale.make(profile)
        return FamiliarFont.jakarta(17 * s.textScale, weight: s.weight, relativeTo: .body)
    }
}

private struct VisionOptionButtonStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !scale.simplifyMotion ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

// MARK: - Live preview

/// A sample cue rendered at the chosen profile's size, the "Preview my settings" pill at that profile's height, and
/// the toast the wearer would see at the top of the screen. The content resolves the profile through
/// `.visionProfile(_:)`, so Reduce Motion, Increase Contrast, Reduce Transparency and Bold Text fold in exactly as
/// they do for the rest of the app; the card chrome stays at the screen's own scale.
private struct VisionPreviewCard: View {
    let profile: VisionProfile
    let previewText: String?
    let previewCount: Int
    let problem: String?
    let shakeTrigger: Int
    let onPreview: () -> Void

    var body: some View {
        VisionPreviewBody(profile: profile,
                          previewText: previewText,
                          previewCount: previewCount,
                          problem: problem,
                          onPreview: onPreview)
            .visionProfile(profile)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard()
            .cardResize()
            .errorShake(trigger: shakeTrigger)
            .accessibilityElement(children: .contain)
    }
}

/// The inside of the preview card; reads the previewed profile's resolved scale from the environment.
private struct VisionPreviewBody: View {
    let profile: VisionProfile
    let previewText: String?
    let previewCount: Int
    let problem: String?
    let onPreview: () -> Void
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Live preview · \(profile.title)")
            Text("Maya, right, close.")
                .font(FamiliarType.companion(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
            Text("You can say hi first.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Button(action: onPreview) {
                Label("Preview my settings", systemImage: "play.circle")
            }
            .buttonStyle(PrimaryPillStyle())
            .accessibilityHint("Says one sample cue, shows it as text and plays the haptic. Camera and microphone stay off")
            if let previewText {
                CueToast(text: previewText, systemImage: "person.wave.2", tint: FamiliarPalette.ocean(scale))
                    .id(previewCount)
            }
            if let problem {
                Text(problem)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Accessibility") {
    NavigationStack {
        AccessibilitySettingsView()
            .environmentObject(AppState())
            .environmentObject(AppCoordinator())
            .environmentObject(FlowRuntime())
    }
}
