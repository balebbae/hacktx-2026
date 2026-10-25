import SwiftUI
import UIKit

/// Familiar's visual language (docs/DESIGN_SPEC.md v1.2): warm ivory canvas, editorial type, white surfaces with
/// 26 pt corners, one accent per meaning, pill controls, and Mimo as the only luminous object on a screen.
/// Every colour has a light and a dark value; nothing is communicated by colour alone.
enum FamiliarPalette {
    static let canvas = dynamic("#F7F8F5", "#101116")
    static let canvasSecondary = dynamic("#EEEDEA", "#191B22")
    static let surface = dynamic("#FFFFFF", "#24262F")
    static let ink = dynamic("#172236", "#F7F7F9")
    static let inkSecondary = dynamic("#576477", "#CED0DA")
    static let stroke = dynamic("#E4E5E8", "#393B47")
    /// Active controls and the consent flow.
    static let ocean = dynamic("#2779E7", "#91B8FF")
    /// Companion pigment.
    static let lilac = dynamic("#A08EF4", "#C3B2FF")
    /// Companion pigment; a consented person.
    static let mint = dynamic("#75D9CF", "#70DBD5")
    static let peach = dynamic("#F5C9AC", "#F5B7AE")
    static let success = dynamic("#127353", "#79E4BB")
    static let warning = dynamic("#925A12", "#FFD18A")
    static let danger = dynamic("#B42336", "#FF929C")

    static let heroRadius: CGFloat = 32
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 18
    static let margin: CGFloat = 22

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

/// Text styles scale with Dynamic Type. SF Pro for reading; SF Rounded only for Mimo's own lines.
enum FamiliarType {
    static let display = Font.system(.largeTitle, weight: .semibold)
    static let titleXL = Font.system(.title, weight: .semibold)
    static let title = Font.system(.title2, weight: .semibold)
    static let body = Font.system(.body)
    static let supporting = Font.system(.subheadline)
    static let micro = Font.system(.footnote, weight: .medium)
    static let companion = Font.system(.title3, design: .rounded, weight: .medium)
    static let mono = Font.system(.footnote, design: .monospaced)
}

/// A white card on the ivory canvas: 26 pt corners, hairline stroke, an ultra-soft shadow.
struct SurfaceCard: ViewModifier {
    var radius: CGFloat = FamiliarPalette.cardRadius
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(FamiliarPalette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(FamiliarPalette.stroke, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
    }
}

extension View {
    func surfaceCard(radius: CGFloat = FamiliarPalette.cardRadius, padding: CGFloat = 20) -> some View {
        modifier(SurfaceCard(radius: radius, padding: padding))
    }

    /// Every Familiar screen sits on the ivory canvas and follows the system appearance.
    func familiarCanvas() -> some View {
        background(FamiliarPalette.canvas.ignoresSafeArea())
    }
}

// MARK: - Pill controls

/// The one solid pill on a screen: ink fill, 56 pt tall.
struct PrimaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.title)
            .foregroundStyle(FamiliarPalette.surface)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(FamiliarPalette.ink, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Ocean-filled pill for the one accent action (Yes on the consent card).
struct AccentPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.title)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(FamiliarPalette.ocean, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// White pill with a hairline, for secondary actions.
struct GhostPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.body.weight(.medium))
            .foregroundStyle(FamiliarPalette.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(FamiliarPalette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
