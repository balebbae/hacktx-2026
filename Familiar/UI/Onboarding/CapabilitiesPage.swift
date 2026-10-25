import SwiftUI

/// Page 2: what Familiar can and cannot do, as three cards and one trust line.
struct CapabilitiesPage: View {
    @Environment(\.onboardingNavigation) private var navigation

    /// Cards rise in when this page is current or the next one over, so a swipe never lands on blank space.
    private var isRevealed: Bool { navigation.currentPage.rawValue + 1 >= OnboardingPage.capabilities.rawValue }

    var body: some View {
        OnboardingPageScaffold(eyebrow: "What to expect",
                               title: "What Familiar can and cannot do",
                               subtitle: "Made for blind and low-vision people. Familiar tells you which of your people are nearby, in a few words, on your terms.",
                               page: .capabilities) {
            VStack(spacing: 14) {
                OnboardingFeatureCard(systemImage: "person.crop.circle.badge.checkmark",
                                      title: "Recognize your people",
                                      detail: "Only people who agree to be remembered. Anyone else is simply “a person”.",
                                      tint: FamiliarPalette.mint)
                    .onboardingReveal(isActive: isRevealed, index: 0)
                OnboardingFeatureCard(systemImage: "hand.wave",
                                      title: "Share small social cues",
                                      detail: "Names, direction, arrivals and a wave. Never feelings or intentions.",
                                      tint: FamiliarPalette.ocean)
                    .onboardingReveal(isActive: isRevealed, index: 1)
                OnboardingFeatureCard(systemImage: "pause.circle",
                                      title: "Stay in control",
                                      detail: "Pause instantly. Remove anyone, any time. Nothing happens behind your back.",
                                      tint: FamiliarPalette.lilac)
                    .onboardingReveal(isActive: isRevealed, index: 2)
            }
            OnboardingTrustLine(text: "Familiar is not a navigation or safety device.")
                .onboardingReveal(isActive: isRevealed, index: 3)
        } actions: {
            Button("Continue") { navigation.advance(from: .capabilities) }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Chooses how Familiar communicates with you")
        }
    }
}

#Preview("Capabilities") {
    CapabilitiesPage()
        .familiarCanvas()
        .environment(\.onboardingNavigation, OnboardingNavigation(currentPage: .capabilities))
}
