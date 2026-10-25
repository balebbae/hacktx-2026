import SwiftUI

/// The five first-launch pages, in order. The raw value is the page's index inside the pager.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, capabilities, communicate, privacy, connect

    var id: Int { rawValue }

    /// Short name read by VoiceOver from the page indicator.
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .capabilities: return "What Familiar can do"
        case .communicate: return "How Familiar communicates"
        case .privacy: return "Privacy promise"
        case .connect: return "Connect glasses"
        }
    }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
}

/// What a page needs from its container: where it is, how to move on, how to finish.
struct OnboardingNavigation {
    var currentPage: OnboardingPage = .welcome
    /// The page a Continue button or the page indicator just asked for, with a counter that changes on every such
    /// request, so that page can move VoiceOver focus to its title. Swipes never set it: focus stays where the user put it.
    var focusPage: OnboardingPage? = nil
    var focusToken: Int = 0
    var goTo: (OnboardingPage) -> Void = { _ in }
    var finish: () -> Void = {}

    func advance(from page: OnboardingPage) {
        if let next = page.next { goTo(next) } else { finish() }
    }
}

private struct OnboardingNavigationKey: EnvironmentKey {
    static let defaultValue = OnboardingNavigation()
}

extension EnvironmentValues {
    var onboardingNavigation: OnboardingNavigation {
        get { self[OnboardingNavigationKey.self] }
        set { self[OnboardingNavigationKey.self] = newValue }
    }
}

/// First launch: Welcome · Capabilities · Communicate · Privacy · Connect glasses, swiped inside `GlassEdgePager`.
/// The pager's `selection` binding is the single source of truth for the current page: swipes update it, and the
/// pages' Continue buttons set it. Sets `onboardingDone` when the user finishes or skips; `RootView` then shows the tabs
/// and `FamiliarApp` boots the pipeline, so no camera or microphone prompt interrupts these pages.
struct OnboardingFlow: View {
    static let storageKey = "onboardingDone"

    @AppStorage(OnboardingFlow.storageKey) private var onboardingDone = false
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex: Int? = OnboardingPage.welcome.rawValue
    /// The last page the pager settled on; `scrollPosition(id:)` can report nil between pages mid-swipe.
    @State private var lastPage: OnboardingPage = .welcome
    @State private var focusPage: OnboardingPage?
    @State private var focusToken = 0

    private var currentPage: OnboardingPage { OnboardingPage(rawValue: pageIndex ?? -1) ?? lastPage }

    var body: some View {
        GlassEdgePager(selection: $pageIndex) {
            WelcomePage()
            CapabilitiesPage()
            CommunicatePage()
            PrivacyPromisePage()
            ConnectGlassesPage()
        }
        .environment(\.onboardingNavigation, navigation)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .familiarCanvas()
        .onChange(of: pageIndex) { _, newIndex in
            guard let newIndex, let page = OnboardingPage(rawValue: newIndex), page != lastPage else { return }
            lastPage = page
            announce(page)
        }
    }

    // MARK: Top bar: progress dots on the left, Skip on the right. A safe-area inset, so every page's scroll view
    // starts under the bar's real height at any text size, and the first two VoiceOver elements on every page.

    private var topBar: some View {
        HStack(alignment: .center) {
            OnboardingProgressDots(current: currentPage, onSelect: { page in go(to: page) })
            Spacer(minLength: 12)
            if currentPage != .connect {
                Button("Skip") { finish() }
                    .buttonStyle(SkipPillStyle())
                    .accessibilityHint("Finishes setup now. Everything here can be changed later in You.")
            }
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilitySortPriority(1)
    }

    // MARK: Navigation

    private var navigation: OnboardingNavigation {
        OnboardingNavigation(currentPage: currentPage,
                             focusPage: focusPage,
                             focusToken: focusToken,
                             goTo: { page in go(to: page) },
                             finish: { finish() })
    }

    private func go(to page: OnboardingPage) {
        focusPage = page
        focusToken += 1
        if reduceMotion || scale.simplifyMotion {
            pageIndex = page.rawValue
        } else {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) { pageIndex = page.rawValue }
        }
    }

    private func finish() {
        FamiliarHaptics.play(.accepted)
        onboardingDone = true
    }

    /// A low-priority announcement, so it queues behind whatever VoiceOver is already reading instead of cutting it off.
    private func announce(_ page: OnboardingPage) {
        var text = AttributedString("\(page.title). Page \(page.rawValue + 1) of \(OnboardingPage.allCases.count).")
        text.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Small white pill for "Skip": quieter than a ghost pill, still at least a 44 pt target.
struct SkipPillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.supporting(scale))
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .padding(.horizontal, 16)
            .frame(minHeight: max(44, scale.hitTarget * 0.8))
            .background(FamiliarPalette.surface(scale), in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !scale.simplifyMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Five dots; the current one stretches into a short pill and slides with a spring. One adjustable VoiceOver element
/// (VoiceOver supplies the swipe-up-or-down hint itself).
struct OnboardingProgressDots: View {
    let current: OnboardingPage
    var onSelect: (OnboardingPage) -> Void = { _ in }
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dot: CGFloat { 8 * scale.iconScale }
    private var count: Int { OnboardingPage.allCases.count }

    var body: some View {
        HStack(spacing: 6 * scale.iconScale) {
            ForEach(OnboardingPage.allCases) { page in
                Capsule()
                    .fill(page == current ? FamiliarPalette.ink(scale) : FamiliarPalette.stroke(scale))
                    .frame(width: page == current ? dot * 3 : dot, height: dot)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .animation(reduceMotion || scale.simplifyMotion ? nil : .spring(response: 0.44, dampingFraction: 0.78), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Page \(current.rawValue + 1) of \(count), \(current.title)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let next = current.next { onSelect(next) }
            case .decrement: if let previous = current.previous { onSelect(previous) }
            @unknown default: break
            }
        }
    }
}

#Preview("Onboarding flow") {
    OnboardingFlow()
        .environmentObject(AppState())
        .environmentObject(AppCoordinator())
}

#Preview("Progress dots") {
    VStack(spacing: 24) {
        OnboardingProgressDots(current: .welcome)
        OnboardingProgressDots(current: .communicate)
        OnboardingProgressDots(current: .connect)
    }
    .padding()
    .familiarCanvas()
}
