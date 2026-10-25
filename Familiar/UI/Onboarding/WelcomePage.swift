import SwiftUI

/// Page 1: Mimo over an aurora halo, "Hello. I'm Mimo.", the tagline, the motto, "Get started", and two quieter
/// pills: "How privacy works" and "Explore a demo" (spec 20.5 §01, clearly simulated: a bundled clip, not the camera).
struct WelcomePage: View {
    static let tagline = "Because everyone deserves to feel seen."
    static let motto = "The finer things in life are felt, not seen."

    @EnvironmentObject var state: AppState
    @Environment(\.visionScale) private var scale
    @Environment(\.onboardingNavigation) private var navigation
    @State private var showPrivacy = false

    private var isRevealed: Bool { navigation.currentPage == .welcome }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    MimoView(state: .idle, size: 240)
                        .padding(.top, 16)
                    copy
                        .padding(.horizontal, FamiliarPalette.margin)
                        .padding(.top, 4)
                }
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnboardingActionBar {
                Button("Get started") { navigation.advance(from: .welcome) }
                    .buttonStyle(PrimaryPillStyle())
                    .accessibilityHint("Shows what Familiar can and cannot do")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        privacyButton
                        demoButton
                    }
                    VStack(spacing: 10) {
                        privacyButton
                        demoButton
                    }
                }
            }
        }
        .background(alignment: .top) { hero }
        .sheet(isPresented: $showPrivacy) { PrivacyPromiseSheet() }
    }

    private var privacyButton: some View {
        Button("How privacy works") { showPrivacy = true }
            .buttonStyle(GhostPillStyle())
            .accessibilityHint("Opens the three privacy promises")
    }

    /// Finishes setup in demo mode: the bundled conversation clip plays instead of the camera, with consenting
    /// actors. Today's device chip then reads "Demo clip"; You → Demo controls switches sources later.
    private var demoButton: some View {
        Button("Explore a demo") { exploreDemo() }
            .buttonStyle(GhostPillStyle())
            .accessibilityHint("Finishes setup with a bundled demo clip instead of the camera. Clearly simulated; you can switch to the camera later in You")
    }

    private func exploreDemo() {
        FamiliarHaptics.play(.accepted)
        let available: [String] = VideoFileFrameSource.availableFixtures()
        if available.contains("conversation") {
            state.source = .fixture("conversation")
        } else if let first = available.first {
            state.source = .fixture(first)
        }
        navigation.finish()
    }

    /// The one luminous form on the page: an aurora halo behind Mimo, clear at both ends so it never meets the
    /// progress bar above or the copy below with a hard edge.
    private var hero: some View {
        AuroraBackground(intensity: scale.highContrast ? 0.35 : 1)
            .frame(height: 440)
            .mask {
                LinearGradient(stops: [
                    Gradient.Stop(color: Color.clear, location: 0),
                    Gradient.Stop(color: Color.black, location: 0.2),
                    Gradient.Stop(color: Color.black, location: 0.55),
                    Gradient.Stop(color: Color.clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }

    /// Three lines, nothing more: Mimo's greeting, the tagline, the motto.
    private var copy: some View {
        VStack(spacing: 14) {
            MimoStatusLine(state: .idle, text: "Hello. I'm Mimo.")
                .onboardingReveal(isActive: isRevealed, index: 0)
            Text(WelcomePage.tagline)
                .font(FamiliarType.display(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .onboardingTitleFocus(.welcome)
                .onboardingReveal(isActive: isRevealed, index: 1)
            Text(WelcomePage.motto)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .onboardingReveal(isActive: isRevealed, index: 2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "How privacy works" from the Welcome page: the same three promises, as a sheet, without leaving the page.
struct PrivacyPromiseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Our promise")
                        Text("How privacy works")
                            .font(FamiliarType.titleXL(scale))
                            .foregroundStyle(FamiliarPalette.ink(scale))
                            .accessibilityAddTraits(.isHeader)
                    }
                    PrivacyPromiseContent()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnboardingActionBar {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryPillStyle())
                    .accessibilityHint("Closes this sheet")
            }
        }
        .familiarCanvas()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(FamiliarPalette.canvas(scale))
    }
}

#Preview("Welcome") {
    WelcomePage()
        .familiarCanvas()
        .environmentObject(AppState())
        .environmentObject(AppCoordinator())
}

#Preview("Privacy sheet") {
    PrivacyPromiseSheet()
}
