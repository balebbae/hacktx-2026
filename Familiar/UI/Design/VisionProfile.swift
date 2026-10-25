import SwiftUI

// MARK: - Vision profile

/// One preference, not a diagnosis. Chosen during onboarding ("How would you like Familiar to communicate?") and
/// changed any time from You → Accessibility. Every size, weight, icon and hit target in the app derives from it
/// through `VisionScale`, which the root puts in the environment (`.visionProfile(state.visionProfile)`).
enum VisionProfile: String, CaseIterable, Codable, Identifiable {
    case balanced
    case lowVision
    case severe
    case nonVisual

    var id: String { rawValue }

    /// Short name for pickers and chips.
    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .lowVision: return "Low vision"
        case .severe: return "Severe"
        case .nonVisual: return "Non-visual"
        }
    }

    /// One sentence under the title. Sentence case, invitational, no exclamation marks.
    var detail: String {
        switch self {
        case .balanced: return "Elegant visuals with concise spoken cues."
        case .lowVision: return "Larger text, stronger contrast and bigger targets."
        case .severe: return "The largest text, bold weight, opaque surfaces and calm motion."
        case .nonVisual: return "Spoken first. VoiceOver summaries lead and visuals stay simple."
        }
    }

    /// SF Symbol for pickers; always shown next to the title, never alone.
    var systemImage: String {
        switch self {
        case .balanced: return "circle.lefthalf.filled"
        case .lowVision: return "textformat.size"
        case .severe: return "textformat.size.larger"
        case .nonVisual: return "ear"
        }
    }

    /// What VoiceOver reads for a picker row: title and detail as one sentence.
    var accessibilityDescription: String { "\(title). \(detail)" }
}

// MARK: - Vision scale

/// Everything derived from the profile, resolved once at the root and read from the environment everywhere.
/// Sizes are multipliers over the balanced design; `hitTarget` is an absolute minimum in points.
struct VisionScale: Equatable {
    /// Multiplies every text size (balanced 1.0 · low vision 1.25 · severe 1.6 · non-visual 1.0).
    let textScale: CGFloat
    /// Multiplies icon and glyph sizes (1.0 · 1.2 · 1.5 · 1.0).
    let iconScale: CGFloat
    /// Default label weight (.semibold · .semibold · .bold · .semibold).
    let weight: Font.Weight
    /// Minimum height of a control in points (52 · 60 · 72 · 60).
    let hitTarget: CGFloat
    /// Opaque surfaces, 2 pt strokes, no translucency, ink on white (false · true · true · false).
    let highContrast: Bool
    /// No drifting gradients or decorative motion; also true when the system Reduce Motion is on.
    let simplifyMotion: Bool
    /// VoiceOver summaries first, visuals secondary (true only for non-visual).
    let spokenFirst: Bool

    static func make(_ p: VisionProfile) -> VisionScale {
        switch p {
        case .balanced:
            return VisionScale(textScale: 1.0, iconScale: 1.0, weight: .semibold, hitTarget: 52,
                               highContrast: false, simplifyMotion: false, spokenFirst: false)
        case .lowVision:
            return VisionScale(textScale: 1.25, iconScale: 1.2, weight: .semibold, hitTarget: 60,
                               highContrast: true, simplifyMotion: false, spokenFirst: false)
        case .severe:
            return VisionScale(textScale: 1.6, iconScale: 1.5, weight: .bold, hitTarget: 72,
                               highContrast: true, simplifyMotion: true, spokenFirst: false)
        case .nonVisual:
            return VisionScale(textScale: 1.0, iconScale: 1.0, weight: .semibold, hitTarget: 60,
                               highContrast: false, simplifyMotion: true, spokenFirst: true)
        }
    }

    /// The default design, used by the deprecated `FamiliarType` shims and by previews.
    static let balanced: VisionScale = VisionScale.make(.balanced)

    /// System settings win over the in-app profile: Reduce Motion freezes motion, Increase Contrast switches to the
    /// high-contrast palette and opaque surfaces, Bold Text raises the label weight. (Reduce Transparency does not
    /// change the palette; the surfaces that draw translucency read it directly.) `visionProfile(_:)` calls this with
    /// the live environment values.
    func honoring(reduceMotion: Bool = false, increaseContrast: Bool = false, boldText: Bool = false) -> VisionScale {
        VisionScale(textScale: textScale,
                    iconScale: iconScale,
                    weight: boldText ? .bold : weight,
                    hitTarget: hitTarget,
                    highContrast: highContrast || increaseContrast,
                    simplifyMotion: simplifyMotion || reduceMotion,
                    spokenFirst: spokenFirst)
    }

    // MARK: Derived tokens

    /// Hairline on the balanced design; a firm 2 pt line in high contrast.
    var strokeWidth: CGFloat { highContrast ? 2 : 1 }

    /// Ultra-soft card shadow; none in high contrast (edges come from the stroke instead).
    var shadowOpacity: Double { highContrast ? 0 : 0.05 }

    /// Translucent surfaces (0.94 white) read as glass over the aurora; high contrast is always opaque.
    var surfaceOpacity: Double { highContrast ? 1 : 0.94 }

    /// Rows that sit side by side in the balanced design stack vertically from here on.
    var prefersStackedLayout: Bool { textScale >= 1.5 }

    /// A text-relative length (a line height, a monogram, a pill's horizontal padding).
    func points(_ base: CGFloat) -> CGFloat { base * textScale }

    /// An icon-relative length (a glyph, a dot on the radar).
    func icon(_ base: CGFloat) -> CGFloat { base * iconScale }

    /// Spacing grows at half the rate of text so large profiles stay dense enough to scan.
    func spacing(_ base: CGFloat) -> CGFloat { base * (1 + (textScale - 1) * 0.5) }

    /// `nil` when motion is simplified, so `.animation(scale.animation(.spring), value:)` degrades to a cut.
    func animation(_ animation: Animation) -> Animation? { simplifyMotion ? nil : animation }
}

// MARK: - Environment

private struct VisionScaleKey: EnvironmentKey {
    static let defaultValue: VisionScale = VisionScale.make(.balanced)
}

extension EnvironmentValues {
    /// Read this in every screen: `@Environment(\.visionScale) private var scale`.
    var visionScale: VisionScale {
        get { self[VisionScaleKey.self] }
        set { self[VisionScaleKey.self] = newValue }
    }
}

/// Resolves the profile against the system accessibility settings and publishes the result. Reduce Transparency is
/// deliberately not folded in: it only asks for opaque surfaces, which `SurfaceCard`, `GhostPillStyle`, `StatusChip`
/// and `AuroraBackground` handle by reading it themselves.
private struct VisionProfileModifier: ViewModifier {
    let profile: VisionProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    private var resolved: VisionScale {
        VisionScale.make(profile).honoring(reduceMotion: reduceMotion,
                                           increaseContrast: contrast == .increased,
                                           boldText: legibilityWeight == .bold)
    }

    func body(content: Content) -> some View {
        content.environment(\.visionScale, resolved)
    }
}

extension View {
    /// Sets an already-resolved scale (previews, tests, a settings preview card).
    func visionScale(_ scale: VisionScale) -> some View {
        environment(\.visionScale, scale)
    }

    /// Set at the root from `AppState.visionProfile`; folds in Reduce Motion, Increase Contrast and Bold Text so
    /// system settings always win (Reduce Transparency is honoured by the translucent surfaces themselves).
    func visionProfile(_ profile: VisionProfile) -> some View {
        modifier(VisionProfileModifier(profile: profile))
    }

    /// Gives an icon-only control the profile's minimum hit target without changing its drawing.
    func visionHitTarget(_ s: VisionScale) -> some View {
        frame(minWidth: s.hitTarget, minHeight: s.hitTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Preview

/// The four profiles side by side, each reading its own scale from the environment.
private struct VisionProfilePreviewRow: View {
    let profile: VisionProfile
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(6)) {
            HStack(spacing: scale.spacing(8)) {
                Image(systemName: profile.systemImage)
                    .visionIcon(scale, base: 18)
                    .foregroundStyle(FamiliarPalette.ocean(scale))
                    .accessibilityHidden(true)
                Text(profile.title)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
            }
            Text(profile.detail)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("Text ×\(scale.textScale, specifier: "%.2f") · icons ×\(scale.iconScale, specifier: "%.1f") · targets \(Int(scale.hitTarget)) pt")
                .font(FamiliarType.mono(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.accessibilityDescription)
    }
}

#Preview("Vision profiles") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(VisionProfile.allCases) { profile in
                VisionProfilePreviewRow(profile: profile)
                    .visionScale(VisionScale.make(profile))
            }
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}
