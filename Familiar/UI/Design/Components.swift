import SwiftUI

// MARK: - Eyebrow

/// Small uppercase label above a headline ("AWARENESS IS ON").
struct Eyebrow: View {
    let text: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        Text(text.uppercased())
            .font(FamiliarType.micro(scale))
            .tracking(1.4 * scale.textScale)
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .accessibilityLabel(text)
    }
}

// MARK: - Status chip

/// Compact pill with an icon and a word or two: device state, cue level, consent state. The icon never carries the
/// meaning alone; VoiceOver reads the text as one element. The text is never truncated: when the row is too narrow
/// (accessibility Dynamic Type, the severe profile) the chip grows in height instead.
struct StatusChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = FamiliarPalette.inkSecondary
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var fill: Color {
        reduceTransparency ? FamiliarPalette.surface : FamiliarPalette.surface(scale)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: scale.spacing(6)) {
            if let systemImage {
                Image(systemName: systemImage)
                    .visionIcon(scale, base: 13)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(FamiliarType.micro(scale))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(scale.highContrast ? FamiliarPalette.ink(scale) : tint)
        .padding(.horizontal, scale.spacing(12))
        .padding(.vertical, scale.spacing(7))
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mic meter

/// Five bars of rising height that follow the microphone level. The number of filled bars, not only their colour,
/// says how loud: under Differentiate Without Color (and in high contrast) the inactive bars are outlines, so the
/// filled silhouette reads without hue.
struct MicMeter: View {
    let level: Float
    var bars: Int = 5
    var color: Color = FamiliarPalette.ocean
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var inactive: Color {
        scale.highContrast ? FamiliarPalette.strokeStrong : FamiliarPalette.stroke
    }

    private var outline: Bool { differentiateWithoutColor || scale.highContrast }

    var body: some View {
        HStack(alignment: .bottom, spacing: scale.icon(3)) {
            ForEach(0..<bars, id: \.self) { index in
                MicBar(isActive: level >= Float(index + 1) / Float(bars),
                       outline: outline,
                       width: scale.icon(5),
                       height: scale.icon(8 + CGFloat(index) * 4),
                       activeColor: scale.highContrast ? FamiliarPalette.ocean(scale) : color,
                       inactiveColor: inactive)
            }
        }
        .animation(scale.animation(.easeOut(duration: 0.12)), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct MicBar: View {
    let isActive: Bool
    let outline: Bool
    let width: CGFloat
    let height: CGFloat
    let activeColor: Color
    let inactiveColor: Color

    var body: some View {
        ZStack {
            if isActive {
                Capsule().fill(activeColor)
            } else if outline {
                Capsule().strokeBorder(inactiveColor, lineWidth: 1.5)
            } else {
                Capsule().fill(inactiveColor)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Cue ticker

/// The last thing Familiar said, large, with the two before it underneath.
struct CueTicker: View {
    let cues: [String]
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var earlier: [String] { Array(cues.dropLast().suffix(2).reversed()) }

    private var earlierLineLimit: Int {
        scale.prefersStackedLayout || dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(4)) {
            if let last = cues.last {
                Text(last)
                    .font(FamiliarType.companion(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .contentTransition(.opacity)
                    .id(last)
            } else {
                Text("We'll speak when something matters.")
                    .font(FamiliarType.companion(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            ForEach(Array(earlier.enumerated()), id: \.offset) { _, cue in
                Text(cue)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .lineLimit(earlierLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last cue: \(cues.last ?? "none yet")")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Privacy banner

/// The trust line that is on every judge-facing screen. Static text, one VoiceOver element; not a heading.
struct PrivacyBanner: View {
    let text: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: scale.spacing(10)) {
            Image(systemName: "lock.shield")
                .visionIcon(scale, base: 17)
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Monogram

/// Soft two-colour monogram for a person without a photo. `size` is the balanced base diameter; the monogram
/// applies the profile's icon scale itself (44 → 66 pt on the severe profile), so callers pass the base and
/// derive any layout offsets from `size * scale.iconScale`. The letter is a fixed-size glyph (it never outgrows the
/// circle under Dynamic Type) and is always dark on the pastel pigments; in light high contrast the pigments switch
/// to the deep teal and violet alternatives with a white letter, and an ink ring makes the edge a line.
struct Monogram: View {
    let name: String
    var size: CGFloat = 44
    @Environment(\.visionScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    private var diameter: CGFloat { scale.icon(size) }

    private var pigments: [Color] {
        scale.highContrast ? [FamiliarPalette.mint(scale), FamiliarPalette.lilac(scale)]
                           : [FamiliarPalette.mint, FamiliarPalette.lilac]
    }

    /// Dark navy on every pastel fill (9.5:1 on mint, 5.8:1 on lilac); white only on the deep light-mode
    /// high-contrast pigments.
    private var letter: Color {
        scale.highContrast && colorScheme == .light ? Color.white : Color(familiarHex: "#172236")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: pigments, startPoint: .topLeading, endPoint: .bottomTrailing))
            if scale.highContrast {
                Circle().strokeBorder(FamiliarPalette.strokeStrong, lineWidth: scale.strokeWidth)
            }
            Text(String(name.prefix(1)).uppercased())
                .font(FamiliarFont.jakartaFixed(diameter * 0.42, weight: scale.weight))
                .foregroundStyle(letter)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Nearby person card

/// One known person in the room: name, direction, distance, one action. Side by side on the balanced design,
/// stacked from the severe profile or accessibility Dynamic Type sizes. One VoiceOver element plus the action.
/// Only known people reach this card, so VoiceOver says "Known person" and never a match percentage: `score` is
/// accepted from the tracker for the callers' convenience but is neither shown nor spoken.
struct NearbyPersonCard: View {
    let name: String
    let direction: String
    let distance: String
    var score: Float? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// What happens when the action is activated ("Calls Marcus"). Defaults to "Opens <action> for <name>".
    var actionHint: String? = nil
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { scale.prefersStackedLayout || dynamicTypeSize.isAccessibilitySize }

    private var layout: AnyLayout {
        stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: scale.spacing(12)))
                : AnyLayout(HStackLayout(alignment: .center, spacing: scale.spacing(14)))
    }

    private var summary: String {
        "\(name). \(direction), \(distance). Known person."
    }

    private func hint(for actionTitle: String) -> String {
        actionHint ?? "Opens \(actionTitle.lowercased()) for \(name)"
    }

    var body: some View {
        layout {
            Monogram(name: name)
            VStack(alignment: .leading, spacing: scale.spacing(2)) {
                Text(name)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                Text("\(direction) · \(distance)")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary)
            if !stacked { Spacer(minLength: scale.spacing(8)) }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GhostPillStyle())
                    .fixedSize(horizontal: !stacked, vertical: false)
                    .accessibilityHint(hint(for: actionTitle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 16)
    }
}

// MARK: - Preview

private struct ComponentsPreview: View {
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(16)) {
            Eyebrow(text: "Awareness is on")
            HStack(spacing: scale.spacing(8)) {
                StatusChip(text: "Glasses connected", systemImage: "eyeglasses", tint: FamiliarPalette.ink)
                StatusChip(text: "Normal cues", systemImage: "waveform")
            }
            MicMeter(level: 0.6)
            CueTicker(cues: ["Normal mode.", "Three people.", "Marcus, ahead, close."])
            NearbyPersonCard(name: "Marcus", direction: "ahead", distance: "close", score: 0.71,
                             actionTitle: "Call", action: {}, actionHint: "Calls Marcus")
            PrivacyBanner(text: "Only people who agreed are ever recognized. Faces stay on this phone.")
        }
        .padding(FamiliarPalette.margin)
    }
}

#Preview("Components · balanced") {
    ScrollView {
        ComponentsPreview().visionScale(VisionScale.make(.balanced))
    }
    .familiarCanvas()
}

#Preview("Components · severe") {
    ScrollView {
        ComponentsPreview().visionScale(VisionScale.make(.severe))
    }
    .familiarCanvas()
}

#Preview("Components · accessibility type") {
    ScrollView {
        ComponentsPreview().visionScale(VisionScale.make(.balanced))
    }
    .familiarCanvas()
    .dynamicTypeSize(.accessibility3)
}
