import SwiftUI

/// Page 5: connect the glasses, or continue with the phone. The page itself only shows the honest source chip; the
/// real `GlassesRegistrationView` (Meta AI registration, camera permission, stream state, live preview) opens in a
/// sheet with its own navigation bar, so nothing here claims a connection the SDK has not reported. Each pill does a
/// different thing: Continue finishes setup, Connect glasses opens the registration.
struct ConnectGlassesPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.onboardingNavigation) private var navigation
    @State private var showGlassesSheet = false

    private var isRevealed: Bool { navigation.currentPage.rawValue + 1 >= OnboardingPage.connect.rawValue }

    var body: some View {
        OnboardingPageScaffold(eyebrow: "Almost there",
                               title: "Let's connect your glasses.",
                               subtitle: "Optional. Familiar works on your iPhone alone, and you can pair glasses any time in You.",
                               page: .connect) {
            OnboardingFeatureCard(systemImage: "eyeglasses",
                                  title: "Ray-Ban Meta glasses",
                                  detail: "They are the camera, microphone and speaker. Your iPhone does the thinking, and the recording light stays on.",
                                  tint: FamiliarPalette.ocean)
                .onboardingReveal(isActive: isRevealed, index: 0)
            OnboardingSourceChip(source: state.source)
                .padding(.horizontal, 4)
                .onboardingReveal(isActive: isRevealed, index: 1)
            OnboardingTrustLine(text: "Familiar only says the glasses are connected once the glasses themselves report it.", systemImage: "checkmark.shield")
                .onboardingReveal(isActive: isRevealed, index: 2)
        } actions: {
            Button("Continue") { navigation.finish() }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Opens Today. You can connect or disconnect glasses any time in You.")
            Button { showGlassesSheet = true } label: {
                Label("Connect glasses", systemImage: "eyeglasses")
            }
            .buttonStyle(GhostPillStyle())
            .accessibilityHint("Opens the Meta AI registration, camera permission and stream controls")
        }
        .sheet(isPresented: $showGlassesSheet) {
            NavigationStack {
                GlassesRegistrationView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showGlassesSheet = false }
                        }
                    }
            }
        }
    }
}

#Preview("Connect glasses") {
    ConnectGlassesPage()
        .familiarCanvas()
        .environmentObject(AppState())
        .environment(\.onboardingNavigation, OnboardingNavigation(currentPage: .connect))
}
