import SwiftUI
import UIKit

// MARK: - Plus Jakarta Sans

/// Plus Jakarta Sans, bundled in `Familiar/Resources/Fonts` (OFL) and registered through `UIAppFonts`.
/// SemiBold (600) is the default weight for every label; Regular only for long paragraphs; Bold only for the display
/// headline. Always go through `FamiliarType` so the vision profile scales everything.
enum FamiliarFont {
    /// Checked once at first use. If the bundle lost the fonts, every call falls back to the rounded system face
    /// so the app still reads well instead of rendering a blank Times New Roman.
    static let isAvailable: Bool = UIFont(name: "PlusJakartaSans-SemiBold", size: 12) != nil

    /// PostScript name for a weight: Bold and heavier → Bold, SemiBold, Medium, everything lighter → Regular.
    static func postScriptName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "PlusJakartaSans-Bold" }
        if weight == .semibold { return "PlusJakartaSans-SemiBold" }
        if weight == .medium { return "PlusJakartaSans-Medium" }
        return "PlusJakartaSans-Regular"
    }

    /// A Jakarta font that still follows Dynamic Type through `relativeTo`. The missing-font fallback scales the
    /// size with the same text style so the app keeps following the system text size either way.
    static func jakarta(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> Font {
        if isAvailable {
            return Font.custom(postScriptName(for: weight), size: size, relativeTo: style)
        }
        let scaled: CGFloat = UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledValue(for: size)
        return Font.system(size: scaled, weight: weight, design: .rounded)
    }

    /// A Jakarta font at a fixed point size, for glyphs whose container is already sized by the vision profile
    /// (the monogram letter, a dot label on the radar). Dynamic Type does not apply, so it cannot outgrow its frame.
    static func jakartaFixed(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if isAvailable {
            return Font.custom(postScriptName(for: weight), fixedSize: size)
        }
        return Font.system(size: size, weight: weight, design: .rounded)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

// MARK: - Type scale

/// The type scale. Every size is already multiplied by `scale.textScale`; the weight comes from `scale.weight`
/// unless the role says otherwise. Base sizes (balanced): display 40 bold · titleXL 32 · title 24 · companion 20 ·
/// control 19 · body 17 · supporting 15 medium · micro 13 · mono 13 medium with tabular digits.
enum FamiliarType {
    /// The welcome headline and the one big promise on a screen. Bold at every profile.
    static func display(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(40 * s.textScale, weight: .bold, relativeTo: .largeTitle)
    }

    /// Screen titles ("In the room", "People").
    static func titleXL(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(32 * s.textScale, weight: s.weight, relativeTo: .title)
    }

    /// Card titles and a person's name.
    static func title(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(24 * s.textScale, weight: s.weight, relativeTo: .title2)
    }

    /// Mimo's own lines and the last cue, large.
    static func companion(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(20 * s.textScale, weight: s.weight, relativeTo: .title3)
    }

    /// Labels inside pills and other controls.
    static func control(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(19 * s.textScale, weight: s.weight, relativeTo: .body)
    }

    /// Critical descriptions; one or two lines.
    static func body(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(17 * s.textScale, weight: s.weight, relativeTo: .body)
    }

    /// Long paragraphs (the privacy promise, what Familiar can and cannot do). Regular weight for reading comfort.
    static func paragraph(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(17 * s.textScale, weight: .regular, relativeTo: .body)
    }

    /// Secondary text under a title. Medium, one step up to SemiBold when the profile is bold.
    static func supporting(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(15 * s.textScale, weight: s.weight == .bold ? .semibold : .medium, relativeTo: .subheadline)
    }

    /// Eyebrows, chips and metadata.
    static func micro(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(13 * s.textScale, weight: s.weight, relativeTo: .footnote)
    }

    /// Timestamps and technical status only: tabular digits so columns do not jitter.
    static func mono(_ s: VisionScale) -> Font {
        FamiliarFont.jakarta(13 * s.textScale, weight: .medium, relativeTo: .footnote).monospacedDigit()
    }
}

// MARK: - Deprecated shims

/// Interim compatibility for screens that have not yet adopted the environment scale. They render the balanced
/// design; prefer the function form with `@Environment(\.visionScale)`.
extension FamiliarType {
    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.display(scale)")
    static var display: Font { display(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.titleXL(scale)")
    static var titleXL: Font { titleXL(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.title(scale)")
    static var title: Font { title(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.body(scale)")
    static var body: Font { body(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.supporting(scale)")
    static var supporting: Font { supporting(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.micro(scale)")
    static var micro: Font { micro(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.companion(scale)")
    static var companion: Font { companion(VisionScale.balanced) }

    @available(*, deprecated, message: "Read @Environment(\\.visionScale) and use FamiliarType.mono(scale)")
    static var mono: Font { mono(VisionScale.balanced) }
}

// MARK: - Icons

extension View {
    /// Sizes an SF Symbol (or any glyph) with the profile's icon scale and weight. Goes through the Jakarta font so
    /// Dynamic Type still applies to the symbol's point size; the symbol weight is set explicitly because a custom
    /// text font does not carry it.
    func visionIcon(_ s: VisionScale, base: CGFloat = 20) -> some View {
        font(FamiliarFont.jakarta(base * s.iconScale, weight: s.weight, relativeTo: .body))
            .fontWeight(s.weight)
    }
}

// MARK: - Preview

private struct TypeRampPreview: View {
    let profile: VisionProfile
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(10)) {
            Eyebrow(text: profile.title)
            Text("Feel at home in every room.").font(FamiliarType.display(scale))
            Text("In the room").font(FamiliarType.titleXL(scale))
            Text("Marcus").font(FamiliarType.title(scale))
            Text("Marcus, ahead, close.").font(FamiliarType.companion(scale))
            Text("Who's here?").font(FamiliarType.control(scale))
            Text("Only people who agreed are ever recognized.").font(FamiliarType.body(scale))
            Text("Faces and consent clips live only on this phone. Cloud services receive text only.")
                .font(FamiliarType.paragraph(scale))
            Text("Met at HackTX · Saturday").font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("Opted in").font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("14:32:08 · 24 fps").font(FamiliarType.mono(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .foregroundStyle(FamiliarPalette.ink(scale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}

#Preview("Type ramp · balanced") {
    ScrollView {
        TypeRampPreview(profile: .balanced)
            .visionScale(VisionScale.make(.balanced))
            .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}

#Preview("Type ramp · severe") {
    ScrollView {
        TypeRampPreview(profile: .severe)
            .visionScale(VisionScale.make(.severe))
            .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}
