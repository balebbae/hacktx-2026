import SwiftUI

/// A short message shown as a `CueToast` above the action bar (the sample cue on the Communicate page).
struct OnboardingToast: Equatable {
    let text: String
    let systemImage: String
}

/// The shared shape of an onboarding page: a scrolling column (eyebrow, title, subtitle, content) and a pinned
/// action bar. Everything reflows at accessibility Dynamic Type sizes; nothing has a fixed height. The progress bar
/// above is a safe-area inset of the pager, so the column starts under it at any size without a fixed inset here.
struct OnboardingPageScaffold<Content: View, Actions: View>: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var toast: OnboardingToast? = nil
    /// Which page this is, so VoiceOver focus can land on the title after a Continue button brings it in.
    var page: OnboardingPage? = nil
    let content: Content
    let actions: Actions

    @Environment(\.visionScale) private var scale

    init(eyebrow: String? = nil,
         title: String,
         subtitle: String? = nil,
         toast: OnboardingToast? = nil,
         page: OnboardingPage? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder actions: () -> Actions) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.toast = toast
        self.page = page
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) { toastView }
            OnboardingActionBar { actions }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow { Eyebrow(text: eyebrow) }
            Text(title)
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .onboardingTitleFocus(page)
            if let subtitle {
                Text(subtitle)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `CueToast` brings its own rise (move, fade, blur, scale) and honours Reduce Motion itself; nothing is layered on top.
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            CueToast(text: toast.text, systemImage: toast.systemImage, tint: FamiliarPalette.ocean)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.bottom, 12)
                .accessibilityHidden(true)   // the cue is spoken (or announced) already; the toast is the visual twin
        }
    }
}

/// Moves VoiceOver focus to a page's title when a Continue button or the page indicator brought that page in
/// (`OnboardingNavigation.focusToken` changes). A swipe never triggers it, so focus stays wherever the user put it.
struct OnboardingTitleFocus: ViewModifier {
    let page: OnboardingPage?

    @Environment(\.onboardingNavigation) private var navigation
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onChange(of: navigation.focusToken) { _, _ in
                guard let page, navigation.focusPage == page else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.45))   // let the pager settle first
                    focused = true
                }
            }
    }
}

extension View {
    func onboardingTitleFocus(_ page: OnboardingPage?) -> some View {
        modifier(OnboardingTitleFocus(page: page))
    }
}

/// Up to two pills pinned to the bottom of a page, on an ivory fade so content scrolls underneath.
struct OnboardingActionBar<Actions: View>: View {
    let actions: Actions
    @Environment(\.visionScale) private var scale

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            actions
        }
        .padding(.horizontal, FamiliarPalette.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(FamiliarPalette.canvas(scale))
        .overlay(alignment: .top) { topEdge }
    }

    @ViewBuilder
    private var topEdge: some View {
        if scale.highContrast {
            Rectangle()
                .fill(FamiliarPalette.stroke(scale))
                .frame(height: scale.strokeWidth)
                .offset(y: -scale.strokeWidth)
        } else {
            LinearGradient(colors: [FamiliarPalette.canvas(scale).opacity(0), FamiliarPalette.canvas(scale)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .offset(y: -24)
                .allowsHitTesting(false)
        }
    }
}

/// One capability or promise: a tinted icon badge, a title and one or two sentences. One VoiceOver element.
struct OnboardingFeatureCard: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color = FamiliarPalette.ocean

    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    badge
                    text
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    badge
                    text
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var badgeSize: CGFloat { 44 * scale.iconScale }

    private var badge: some View {
        ZStack {
            Circle().fill(scale.highContrast ? FamiliarPalette.canvasSecondary : tint.opacity(0.14))
            Image(systemName: systemImage)
                .visionIcon(scale, base: 20)
                .foregroundStyle(scale.highContrast ? FamiliarPalette.ink(scale) : tint)
        }
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(FamiliarType.paragraph(scale))   // the one place Regular weight is right: a sentence or two to read
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A quiet line with a small icon, for the trust statements at the bottom of a page.
struct OnboardingTrustLine: View {
    let text: String
    var systemImage: String = "info.circle"

    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .visionIcon(scale, base: 16)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The honest device pill: which source the app is set to use right now. It never says "connected"; only the
/// glasses SDK can (inside `GlassesRegistrationView`). Quiet tint on purpose.
struct OnboardingSourceChip: View {
    let source: Services.Source

    var body: some View {
        StatusChip(text: label, systemImage: symbol)
            .accessibilityLabel("Right now: \(label)")
    }

    private var label: String {
        switch source {
        case .phone: return "Using iPhone"
        case .glasses: return "Using glasses"
        case .fixture: return "Demo mode"
        }
    }

    private var symbol: String {
        switch source {
        case .phone: return "iphone"
        case .glasses: return "eyeglasses"
        case .fixture: return "film"
        }
    }
}

/// Staggered entrance for the cards on a page: fade and a 14 pt rise once the page is current or next in line, so
/// swiping never lands on an empty page. A page that is already active renders visible on its first frame (so an
/// `ImageRenderer` snapshot is complete); the stagger plays only for pages activated later. Still under Reduce Motion
/// or a simplified-motion profile.
struct OnboardingReveal: ViewModifier {
    let isActive: Bool
    let index: Int

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(isActive: Bool, index: Int) {
        self.isActive = isActive
        self.index = index
        _shown = State(initialValue: isActive)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onChange(of: isActive) { _, active in
                guard active, !shown else { return }
                if reduceMotion || scale.simplifyMotion {
                    shown = true
                } else {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.78).delay(0.08 * Double(index))) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func onboardingReveal(isActive: Bool, index: Int) -> some View {
        modifier(OnboardingReveal(isActive: isActive, index: index))
    }
}

#Preview("Scaffold") {
    OnboardingPageScaffold(eyebrow: "Preview", title: "A page title that wraps onto two lines", subtitle: "Supporting copy sits under the title in secondary ink.") {
        OnboardingFeatureCard(systemImage: "person.crop.circle.badge.checkmark", title: "Recognize your people", detail: "Only people who agree to be remembered.", tint: FamiliarPalette.mint)
        OnboardingFeatureCard(systemImage: "hand.wave", title: "Share small social cues", detail: "Names, direction, arrivals and a wave. Never feelings or intentions.")
        OnboardingSourceChip(source: .phone)
        OnboardingTrustLine(text: "Familiar is not a navigation or safety device.")
    } actions: {
        Button("Continue") {}.buttonStyle(PrimaryPillStyle())
        Button("Not now") {}.buttonStyle(GhostPillStyle())
    }
    .familiarCanvas()
}
