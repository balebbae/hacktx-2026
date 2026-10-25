import SwiftUI

/// Text with a soft band of light sweeping through it, for waiting states ("Thinking…", "Listening…").
/// The glyphs are always drawn at full `color`, so the label never loses contrast; a narrow band of `highlight`
/// (white by default) is masked to the glyphs and slides across on a `TimelineView`, lightening each glyph for a
/// moment as it passes. Static under `simplifyMotion`, Reduce Motion and high contrast. VoiceOver reads the plain
/// text once. On light text (white on an ink pill) the white band is invisible; pass a tinted `highlight` there.
struct ShimmerText: View {
    let text: String
    let font: Font
    let color: Color
    /// Colour of the passing band. White lightens dark ink; use a pale accent for text that is already light.
    var highlight: Color = Color.white
    /// Seconds for one sweep.
    var period: Double = 2.1

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String, font: Font, color: Color) {
        self.text = text
        self.font = font
        self.color = color
    }

    init(_ text: String, font: Font, color: Color, highlight: Color) {
        self.text = text
        self.font = font
        self.color = color
        self.highlight = highlight
    }

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) && !scale.highContrast }

    var body: some View {
        Group {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let progress = ShimmerText.progress(at: context.date, period: period)
                    label
                        .overlay {
                            ShimmerText.sweep(color: highlight, progress: progress)
                                .mask { Text(text).font(font) }
                                .allowsHitTesting(false)
                        }
                }
            } else {
                label
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
    }

    /// 0…1 position of the band, looping every `period` seconds.
    static func progress(at date: Date, period: Double) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let wrapped = t.truncatingRemainder(dividingBy: period)
        return (wrapped < 0 ? wrapped + period : wrapped) / period
    }

    /// A narrow band of `color` (at most 55 % opaque) that travels from before the leading edge to after the trailing
    /// edge. Composited over the full-colour glyphs it reads as a sheen, not as dimmed text.
    static func sweep(color: Color, progress: Double) -> LinearGradient {
        let x = -0.7 + progress * 2.4
        let stops: [Gradient.Stop] = [
            .init(color: color.opacity(0), location: 0),
            .init(color: color.opacity(0.3), location: 0.42),
            .init(color: color.opacity(0.55), location: 0.5),
            .init(color: color.opacity(0.3), location: 0.58),
            .init(color: color.opacity(0), location: 1),
        ]
        return LinearGradient(gradient: Gradient(stops: stops),
                              startPoint: UnitPoint(x: x - 0.45, y: 0.5),
                              endPoint: UnitPoint(x: x + 0.45, y: 0.5))
    }
}

// MARK: - Previews

private struct ShimmerTextPreview: View {
    @Environment(\.visionScale) private var scale
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ShimmerText("Thinking…", font: FamiliarType.companion(scale), color: FamiliarPalette.lilac(scale))
            ShimmerText("Listening for your answer", font: FamiliarType.title(scale), color: FamiliarPalette.ink(scale))
            ShimmerText("Looking for people who said yes", font: FamiliarType.body(scale), color: FamiliarPalette.inkSecondary(scale))
            ShimmerText("Checking…", font: FamiliarType.control(scale), color: FamiliarPalette.canvas(scale), highlight: FamiliarPalette.lilac)
                .padding(.horizontal, 24)
                .frame(minHeight: scale.hitTarget)
                .background(FamiliarPalette.ink(scale), in: Capsule())
        }
        .padding(FamiliarPalette.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .familiarCanvas()
    }
}

#Preview("Shimmer text") {
    ShimmerTextPreview()
}

#Preview("Shimmer text · low vision") {
    ShimmerTextPreview()
        .environment(\.visionScale, VisionScale.make(.lowVision))
}
