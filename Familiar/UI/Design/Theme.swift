import SwiftUI
import UIKit

// MARK: - Palette

/// Familiar's visual language (docs/DESIGN_SPEC.md §3, §20.6): warm ivory canvas, editorial type, white surfaces
/// with 26 pt corners, one accent per meaning, pill controls, and one luminous object per screen (Mimo or the aurora).
/// Every colour has a light and a dark value; nothing is communicated by colour alone. The `(_ scale:)` helpers pick
/// the high-contrast alternative when the vision profile (or Increase Contrast) asks for it.
enum FamiliarPalette {
    // Canvas and ink
    static let canvas = dynamic("#F7F8F5", "#101116")
    static let canvasSecondary = dynamic("#EEEDEA", "#191B22")
    static let surface = dynamic("#FFFFFF", "#24262F")
    static let ink = dynamic("#172236", "#F7F7F9")
    static let inkSecondary = dynamic("#576477", "#CED0DA")
    static let stroke = dynamic("#E4E5E8", "#393B47")

    // Accents: one meaning each
    /// Active controls and the consent flow. 5.0:1 on white and 4.7:1 on the canvas, so it also works as text.
    static let ocean = dynamic("#1F6CD6", "#91B8FF")
    /// The label colour on an ocean fill: white in light, deep navy on the pale dark-mode blue.
    static let onOcean = dynamic("#FFFFFF", "#0B1A33")
    /// Companion pigment; thinking.
    static let lilac = dynamic("#A08EF4", "#C3B2FF")
    /// Companion pigment; a consented person.
    static let mint = dynamic("#75D9CF", "#70DBD5")
    /// Warmth; a contact.
    static let peach = dynamic("#F5C9AC", "#F5B7AE")
    static let success = dynamic("#127353", "#79E4BB")
    static let warning = dynamic("#925A12", "#FFD18A")
    static let danger = dynamic("#B42336", "#FF929C")
    /// Keyboard and Switch Control focus ring.
    static let focus = dynamic("#1B64D8", "#8FB6FF")

    // High-contrast alternatives (spec §20.6), reached through the scale helpers below
    static let canvasHighContrast = dynamic("#FFFFFF", "#000000")
    static let inkHighContrast = dynamic("#07111F", "#FFFFFF")
    static let inkSecondaryHighContrast = dynamic("#26364B", "#E6E8F0")
    static let strokeStrong = dynamic("#26364B", "#CED0DA")
    static let oceanHighContrast = dynamic("#0053B8", "#B5D1FF")
    static let lilacHighContrast = dynamic("#6741B8", "#C3B2FF")
    static let mintHighContrast = dynamic("#00776D", "#70DBD5")
    static let focusHighContrast = dynamic("#003B8E", "#8FB6FF")

    // Aurora stops: the shifting hero gradient, blue → orange → purple → sky
    static let auroraBlue = Color(familiarHex: "#2779E7")
    static let auroraOrange = Color(familiarHex: "#F5A66B")
    static let auroraPurple = Color(familiarHex: "#A08EF4")
    static let auroraSky = Color(familiarHex: "#79C9F7")

    // Geometry
    static let heroRadius: CGFloat = 32
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 18
    static let margin: CGFloat = 22

    // MARK: Scale-aware helpers

    /// Hairline normally; the strong ink-blue line in high contrast.
    static func stroke(_ s: VisionScale) -> Color { s.highContrast ? strokeStrong : stroke }

    /// Card fill: glassy 0.94 white on the balanced design, always opaque in high contrast.
    static func surface(_ s: VisionScale) -> Color { s.highContrast ? surface : surface.opacity(s.surfaceOpacity) }

    /// Pure white (or pure black in dark mode) in high contrast so ink sits on the strongest ground.
    static func canvas(_ s: VisionScale) -> Color { s.highContrast ? canvasHighContrast : canvas }

    static func ink(_ s: VisionScale) -> Color { s.highContrast ? inkHighContrast : ink }

    static func inkSecondary(_ s: VisionScale) -> Color { s.highContrast ? inkSecondaryHighContrast : inkSecondary }

    /// Accent that passes 4.5:1 as text on white at every profile; 7:1 and more in high contrast.
    static func ocean(_ s: VisionScale) -> Color { s.highContrast ? oceanHighContrast : ocean }

    /// Lilac as a meaning-carrying tint (thinking): deep violet in light high contrast.
    static func lilac(_ s: VisionScale) -> Color { s.highContrast ? lilacHighContrast : lilac }

    /// Mint as a meaning-carrying tint (a consented person): deep teal in light high contrast.
    static func mint(_ s: VisionScale) -> Color { s.highContrast ? mintHighContrast : mint }

    /// Focus ring colour; darker in light high contrast.
    static func focus(_ s: VisionScale) -> Color { s.highContrast ? focusHighContrast : focus }

    private static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(familiarHex: dark) : UIColor(familiarHex: light)
        })
    }
}

extension UIColor {
    convenience init(familiarHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// A fixed sRGB colour from "#RRGGBB" (the aurora stops, which do not change with appearance).
    init(familiarHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Surfaces

/// A white card on the ivory canvas: 26 pt corners, hairline stroke, an ultra-soft shadow under the shape only.
/// `padding` is a base value in points; the modifier scales it with the profile (`scale.spacing`), so callers pass
/// the balanced number. In high contrast (or under Reduce Transparency) the fill is opaque, the stroke is 2 pt
/// ink-blue and no shadow is drawn at all.
struct SurfaceCard: ViewModifier {
    var radius: CGFloat = FamiliarPalette.cardRadius
    var padding: CGFloat = 20
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var fillColor: Color {
        reduceTransparency ? FamiliarPalette.surface : FamiliarPalette.surface(scale)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(scale.spacing(padding))
            .background(
                shape
                    .fill(fillColor)
                    .shadow(color: Color.black.opacity(scale.shadowOpacity),
                            radius: scale.highContrast ? 0 : 12,
                            y: scale.highContrast ? 0 : 4)
            )
            .overlay(shape.strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
    }
}

/// The ivory ground under every screen; pure white (or black) in high contrast.
private struct FamiliarCanvasModifier: ViewModifier {
    @Environment(\.visionScale) private var scale

    func body(content: Content) -> some View {
        content.background(FamiliarPalette.canvas(scale).ignoresSafeArea())
    }
}

extension View {
    /// `padding` is the balanced base; the card scales it with the profile.
    func surfaceCard(radius: CGFloat = FamiliarPalette.cardRadius, padding: CGFloat = 20) -> some View {
        modifier(SurfaceCard(radius: radius, padding: padding))
    }

    /// Every Familiar screen sits on the ivory canvas and follows the system appearance.
    func familiarCanvas() -> some View {
        modifier(FamiliarCanvasModifier())
    }
}

// MARK: - Pill controls

/// Shared pill chrome: the label reads the control font, grows to the profile's hit target, never clips, and gives
/// the 0.97 press squeeze for 100 ms. When motion is simplified the press is acknowledged with a short dim instead.
private struct PillChrome: ViewModifier {
    let isPressed: Bool
    let fill: Color
    let foreground: Color
    let stroke: Color?
    @Environment(\.visionScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    private var pillOpacity: Double {
        if !isEnabled { return 0.45 }
        return isPressed && scale.simplifyMotion ? 0.8 : 1
    }

    func body(content: Content) -> some View {
        content
            .font(FamiliarType.control(scale))
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, scale.spacing(24))
            .padding(.vertical, scale.spacing(12))
            .frame(maxWidth: .infinity, minHeight: scale.hitTarget)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke ?? Color.clear, lineWidth: stroke == nil ? 0 : scale.strokeWidth))
            .contentShape(Capsule())
            .opacity(pillOpacity)
            .scaleEffect(isPressed && !scale.simplifyMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

/// The one solid pill on a screen: ink fill, white label.
struct PrimaryPillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillChrome(isPressed: configuration.isPressed,
                                 fill: FamiliarPalette.ink(scale),
                                 foreground: FamiliarPalette.canvas(scale),
                                 stroke: nil))
    }
}

/// Ocean-filled pill for the one accent action (Yes on the consent card). The label uses `onOcean`, which stays
/// legible on the pale dark-mode blue.
struct AccentPillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillChrome(isPressed: configuration.isPressed,
                                 fill: FamiliarPalette.ocean(scale),
                                 foreground: FamiliarPalette.onOcean,
                                 stroke: nil))
    }
}

/// White pill with a hairline (2 pt ink in high contrast), for secondary actions.
struct GhostPillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillChrome(isPressed: configuration.isPressed,
                                 fill: reduceTransparency ? FamiliarPalette.surface : FamiliarPalette.surface(scale),
                                 foreground: FamiliarPalette.ink(scale),
                                 stroke: FamiliarPalette.stroke(scale)))
    }
}

// MARK: - Preview

private struct PillPreview: View {
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: scale.spacing(12)) {
            Button("Who's here?") {}.buttonStyle(PrimaryPillStyle())
            Button("Yes, remember me") {}.buttonStyle(AccentPillStyle())
            Button("Pause") {}.buttonStyle(GhostPillStyle())
            Button("Disabled") {}.buttonStyle(GhostPillStyle()).disabled(true)
            Text("A white card on the ivory canvas with a hairline and an ultra-soft shadow.")
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
        }
        .padding(FamiliarPalette.margin)
    }
}

#Preview("Pills · balanced") {
    PillPreview()
        .visionScale(VisionScale.make(.balanced))
        .familiarCanvas()
}

#Preview("Pills · low vision") {
    PillPreview()
        .visionScale(VisionScale.make(.lowVision))
        .familiarCanvas()
}

#Preview("Pills · dark") {
    PillPreview()
        .visionScale(VisionScale.make(.balanced))
        .familiarCanvas()
        .preferredColorScheme(.dark)
}
