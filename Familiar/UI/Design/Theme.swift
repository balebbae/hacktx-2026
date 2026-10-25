import SwiftUI

/// Familiar's visual language: dark-first and high contrast for a bright hackathon hall, one colour per meaning,
/// huge touch targets, rounded type. Liquid Glass on iOS 26, plain materials before that.
enum FamiliarTheme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    /// A consented person. Also the "listening" state.
    static let known = Color(red: 0.36, green: 0.93, blue: 0.56)
    /// "A person": never a name, never a description.
    static let unknown = Color(white: 0.66)
    /// Consent flow and system chrome.
    static let consent = Color(red: 0.42, green: 0.66, blue: 1.00)
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.40)
    static let cardRadius: CGFloat = 24
    /// Minimum height of anything the wearer taps without looking.
    static let minTarget: CGFloat = 88
}

extension Font {
    static let familiarHero = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let familiarTitle = Font.system(.title2, design: .rounded).weight(.semibold)
    static let familiarBody = Font.system(.body, design: .rounded)
    static let familiarCaption = Font.system(.footnote, design: .rounded).weight(.medium)
    static let familiarMono = Font.system(.footnote, design: .monospaced)
}

/// Liquid Glass on iOS 26; a material with a hairline on earlier systems.
struct GlassCard: ViewModifier {
    var radius: CGFloat = FamiliarTheme.cardRadius
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder((tint ?? .white).opacity(0.18), lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = FamiliarTheme.cardRadius, tint: Color? = nil) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }

    /// Every Familiar screen: near-black background, always dark so colours read the same on the table.
    func familiarScreen() -> some View {
        background(FamiliarTheme.background.ignoresSafeArea()).preferredColorScheme(.dark)
    }
}
