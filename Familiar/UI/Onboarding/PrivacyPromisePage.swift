import SwiftUI

/// Page 4: the three promises and the one line that sums them up. Continue opens the permissions checklist as the
/// next step (so the system prompts arrive with context, not at launch); finishing it moves on to the glasses page.
struct PrivacyPromisePage: View {
    @Environment(\.onboardingNavigation) private var navigation
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @State private var showReadiness = false

    private var isRevealed: Bool { navigation.currentPage.rawValue + 1 >= OnboardingPage.privacy.rawValue }

    var body: some View {
        OnboardingPageScaffold(eyebrow: "Our promise",
                               title: "How privacy works",
                               page: .privacy) {
            PrivacyPromiseContent(isRevealed: isRevealed)
        } actions: {
            Button("Continue") { showReadiness = true }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Opens the permissions checklist: camera, microphone, speech, contacts and location, one at a time")
            Button("Not now") { navigation.advance(from: .privacy) }
                .buttonStyle(GhostPillStyle())
                .accessibilityHint("Skips permissions for now. Familiar asks again on Today.")
        }
        .sheet(isPresented: $showReadiness) {
            ReadinessView(onDone: {
                showReadiness = false
                readinessDone = true
                navigation.advance(from: .privacy)
            })
        }
    }
}

/// The promises themselves; shared by the Privacy page and the "How privacy works" sheet on Welcome.
struct PrivacyPromiseContent: View {
    var isRevealed: Bool = true
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 14) {
            OnboardingFeatureCard(systemImage: "checkmark.seal",
                                  title: "Only people who say yes",
                                  detail: "Someone is remembered only after they agree out loud or tap Yes. You cannot add anyone on your own.",
                                  tint: FamiliarPalette.mint)
                .onboardingReveal(isActive: isRevealed, index: 0)
            OnboardingFeatureCard(systemImage: "lock.shield",
                                  title: "Faces stay on your phone",
                                  detail: "Face data and consent clips stay on this phone. The optional cloud fallback in You sends one small face crop and discards it. Remove anyone and everything about them is deleted.",
                                  tint: FamiliarPalette.ocean)
                .onboardingReveal(isActive: isRevealed, index: 1)
            OnboardingFeatureCard(systemImage: "speaker.wave.2",
                                  title: "You control when Familiar speaks",
                                  detail: "Quiet, normal or chatty. Pause with one tap. Cues are a few words, and silence is the default.",
                                  tint: FamiliarPalette.lilac)
                .onboardingReveal(isActive: isRevealed, index: 2)
        }
        summary
            .onboardingReveal(isActive: isRevealed, index: 3)
        OnboardingTrustLine(text: "The glasses' recording light stays on whenever the camera is.", systemImage: "light.max")
            .onboardingReveal(isActive: isRevealed, index: 4)
    }

    /// The pull-quote. Not a heading: it is one static element, so it stays out of the Headings rotor.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "text.quote")
                .visionIcon(scale, base: 20)
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .accessibilityHidden(true)
            Text("Only text ever leaves the phone.")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Privacy promise") {
    PrivacyPromisePage()
        .familiarCanvas()
        .environment(\.onboardingNavigation, OnboardingNavigation(currentPage: .privacy))
}
