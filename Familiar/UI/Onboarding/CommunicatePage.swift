import SwiftUI
import AVFoundation
import UIKit

/// Page 3: "How would you like Familiar to communicate?" The vision profile picker, a live preview block that
/// re-scales with the chosen profile, and a sample cue spoken through the app's own speaker.
struct CommunicatePage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.visionScale) private var scale
    @Environment(\.onboardingNavigation) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toast: OnboardingToast?
    @State private var toastTask: Task<Void, Never>?
    @State private var lastSpoken: String?
    @State private var localVoice = OnboardingSampleVoice()

    /// The one cue every preview uses. Maya is the demo's consenting friend.
    static let sampleCue = Phrasebook.appeared(name: "Maya", bearing: .atClock(2), distance: .close)

    var body: some View {
        OnboardingPageScaffold(eyebrow: "Your way",
                               title: "How would you like Familiar to communicate?",
                               subtitle: "A preference, not a diagnosis. Text, icons and controls follow it everywhere, and you can change it any time in You.",
                               toast: toast,
                               page: .communicate) {
            OnboardingProfilePicker(selection: $state.visionProfile)
            CuePreviewBlock(profile: state.visionProfile,
                            source: state.source,
                            mode: state.mode,
                            lastSpoken: lastSpoken,
                            usesSystemVoice: coordinator.services == nil,
                            onPlay: playSample)
        } actions: {
            Button("Continue") { navigation.advance(from: .communicate) }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Shows the privacy promise")
        }
    }

    // MARK: Sample cue

    /// The app's own speaker when the pipeline is running; otherwise the system voice (the pipeline boots after
    /// onboarding so no camera or microphone prompt interrupts these pages), or a VoiceOver announcement so a
    /// VoiceOver user hears it once rather than twice.
    private func playSample() {
        let text = CommunicatePage.sampleCue
        lastSpoken = text
        FamiliarHaptics.play(.cue)
        if let speaker = coordinator.services?.speaker {
            let utterance = Utterance(text: text, priority: 1, category: "preview", personID: nil, dedupeKey: nil, audience: .user, earcon: true)
            Task { await speaker.speak(utterance) }
        } else if UIAccessibility.isVoiceOverRunning {
            AccessibilityNotification.Announcement(text).post()
        } else {
            localVoice.speak(text)
        }
        showToast(OnboardingToast(text: text, systemImage: "person.wave.2"))
    }

    private func showToast(_ next: OnboardingToast) {
        toastTask?.cancel()
        let animation: Animation? = (reduceMotion || scale.simplifyMotion) ? nil : .spring(response: 0.44, dampingFraction: 0.78)
        withAnimation(animation) { toast = next }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            withAnimation(animation) { toast = nil }
        }
    }
}

/// Speaks the sample cue with the system voice while the pipeline is not running yet. One string, nothing queued;
/// not a `Speaker` and not a service: the real voice takes over as soon as the coordinator has booted.
final class OnboardingSampleVoice {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }
}

// MARK: - Profile picker

/// Four large cards, one per `VisionProfile`. Selection is a heavier ocean outline plus a check mark, never colour
/// alone. (The You tab has its own `VisionProfilePicker`; this one is laid out for the onboarding column.)
struct OnboardingProfilePicker: View {
    @Binding var selection: VisionProfile
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ForEach(VisionProfile.allCases) { profile in
                OnboardingProfileCard(profile: profile, isSelected: profile == selection) {
                    select(profile)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Communication profile")
    }

    private func select(_ profile: VisionProfile) {
        guard profile != selection else { return }
        if reduceMotion || scale.simplifyMotion {
            selection = profile
        } else {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) { selection = profile }
        }
    }
}

struct OnboardingProfileCard: View {
    let profile: VisionProfile
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize || scale.prefersStackedLayout }

    var body: some View {
        Button(action: action) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { badge; Spacer(minLength: 8); check }
                        text
                    }
                } else {
                    HStack(spacing: 16) {
                        badge
                        text
                        Spacer(minLength: 8)
                        check
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: scale.hitTarget)
            .padding(18)
            .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? FamiliarPalette.ocean(scale) : FamiliarPalette.stroke(scale),
                                  lineWidth: isSelected ? scale.strokeWidth + 1 : scale.strokeWidth)   // always one step heavier than its neighbours, also in high contrast
            )
            .shadow(color: Color.black.opacity(scale.shadowOpacity), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
        }
        .buttonStyle(OnboardingCardPressStyle())
        .accessibilityLabel(profile.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "" : "Switches to this profile and updates the preview below")
    }

    private var badgeSize: CGFloat { 44 * scale.iconScale }

    /// In high contrast the selected badge gets a shaded well, a second shape cue next to the heavier outline.
    private var badgeFill: Color {
        if scale.highContrast {
            return isSelected ? FamiliarPalette.ink(scale).opacity(0.08) : FamiliarPalette.canvasSecondary
        }
        return FamiliarPalette.ocean.opacity(isSelected ? 0.16 : 0.1)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(badgeFill)
            Image(systemName: profile.systemImage)
                .visionIcon(scale, base: 20)
                .foregroundStyle(scale.highContrast || isSelected ? FamiliarPalette.ink(scale) : FamiliarPalette.ocean(scale))
        }
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.title)
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
            Text(profile.detail)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var check: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .visionIcon(scale, base: 24)
            .foregroundStyle(isSelected ? FamiliarPalette.ocean(scale) : FamiliarPalette.stroke(scale))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// The 0.97 press scale from the spec, for cards that act as buttons.
struct OnboardingCardPressStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !scale.simplifyMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Live preview

/// What a cue looks like under the chosen profile. The block resolves `visionScale` for its own subtree through
/// `visionProfile(_:)`, so every design-system component inside follows the card the user just tapped (with the
/// system accessibility settings folded in), not the app-wide setting. The chips show the real source and cue level.
struct CuePreviewBlock: View {
    let profile: VisionProfile
    var source: Services.Source = .phone
    var mode: ChatterMode = .normal
    var lastSpoken: String? = nil
    /// True while the pipeline (and so the app's own voice) has not booted: the sample is the iPhone's voice, and the
    /// block says so instead of implying it is the voice the wearer will hear later.
    var usesSystemVoice: Bool = false
    let onPlay: () -> Void

    var body: some View {
        CuePreviewBody(source: source, mode: mode, lastSpoken: lastSpoken, usesSystemVoice: usesSystemVoice, onPlay: onPlay)
            .visionProfile(profile)
            .cardResize()
    }
}

private struct CuePreviewBody: View {
    let source: Services.Source
    let mode: ChatterMode
    var lastSpoken: String?
    var usesSystemVoice: Bool = false
    let onPlay: () -> Void
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize || scale.prefersStackedLayout }

    private var playHint: String {
        usesSystemVoice
            ? "Speaks \"\(CommunicatePage.sampleCue)\" with the iPhone's voice. Your chosen voice takes over after setup"
            : "Speaks \"\(CommunicatePage.sampleCue)\" through the current voice"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Live preview")
            cueRow
            statusRow
            notes
            Button(action: onPlay) {
                Label(lastSpoken == nil ? "Play a sample cue" : "Play it again", systemImage: "speaker.wave.2")
            }
            .buttonStyle(GhostPillStyle())
            .accessibilityHint(playHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous)
                .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth)
        )
        .shadow(color: Color.black.opacity(scale.shadowOpacity), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview of a cue")
    }

    private var cueRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.wave.2")
                .visionIcon(scale, base: 28)
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(CommunicatePage.sampleCue)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Someone you know, on your right, close by.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The real state, never a claim: the source the app is set to use and the current cue level.
    private var statusRow: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingSourceChip(source: source)
                    modeChip
                }
            } else {
                HStack(spacing: 8) {
                    OnboardingSourceChip(source: source)
                    modeChip
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var modeChip: some View {
        StatusChip(text: "\(mode.title) cues", systemImage: "speaker.wave.2")
    }

    @ViewBuilder
    private var notes: some View {
        if usesSystemVoice {
            Text("The sample uses the iPhone's voice for now. Your chosen voice takes over after setup.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        if scale.spokenFirst {
            Text("Spoken first: cues are spoken aloud and VoiceOver summaries lead; on-screen text stays secondary.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        if scale.highContrast {
            Text("High contrast: opaque surfaces, stronger outlines, ink on white.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let lastSpoken {
            Text("Last spoken: \(lastSpoken)")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Communicate") {
    CommunicatePage()
        .familiarCanvas()
        .environmentObject(AppState())
        .environmentObject(AppCoordinator())
        .environment(\.onboardingNavigation, OnboardingNavigation(currentPage: .communicate))
}

#Preview("Preview block per profile") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(VisionProfile.allCases) { profile in
                CuePreviewBlock(profile: profile, onPlay: {})
            }
        }
        .padding()
    }
    .familiarCanvas()
}
