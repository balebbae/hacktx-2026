import SwiftUI

/// A number whose digits roll into place when the value changes: each digit uses `.contentTransition(.numericText())`
/// and pops through a short blur + scale, staggered left to right. Grouping separators stay still.
/// Under `simplifyMotion` or Reduce Motion the digits simply crossfade. VoiceOver reads the whole number once.
struct NumberPop: View {
    let value: Int
    let font: Font
    let color: Color

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Int, font: Font, color: Color) {
        self.value = value
        self.font = font
        self.color = color
    }

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }
    private var characters: [Character] { Array(value.formatted(.number)) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(characters.enumerated()), id: \.offset) { pair in
                NumberPopDigit(character: pair.element,
                               index: pair.offset,
                               trigger: value,
                               font: font,
                               color: color,
                               animates: animates)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.formatted(.number))
    }
}

/// One glyph of a `NumberPop`.
private struct NumberPopDigit: View {
    let character: Character
    let index: Int
    let trigger: Int
    let font: Font
    let color: Color
    let animates: Bool

    private var delay: Double { Double(index) * FamiliarMotion.stagger }
    private var isDigit: Bool { character.isNumber }

    var body: some View {
        if animates && isDigit {
            glyph
                .contentTransition(.numericText(value: Double(character.wholeNumberValue ?? 0)))
                .animation(FamiliarMotion.spring.delay(delay), value: trigger)
                .phaseAnimator([0.0, 1.0], trigger: trigger) { content, phase in
                    content
                        .blur(radius: phase * 5)
                        .scaleEffect(1 + phase * 0.12)
                } animation: { phase in
                    phase > 0.5 ? Animation.easeOut(duration: 0.12).delay(delay) : FamiliarMotion.spring.delay(delay)
                }
        } else if isDigit {
            glyph
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: trigger)
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Text(String(character))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Previews

#Preview("Number pop") {
    struct Host: View {
        @Environment(\.visionScale) private var scale
        @State private var count: Int = 3
        var body: some View {
            VStack(spacing: 28) {
                VStack(spacing: 4) {
                    NumberPop(value: count, font: FamiliarType.display(scale), color: FamiliarPalette.ink(scale))
                    Text(count == 1 ? "person chose to connect" : "people chose to connect")
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
                HStack(spacing: 12) {
                    Button("Fewer") { count = max(0, count - 1) }.buttonStyle(GhostPillStyle())
                    Button("More") { count += 1 }.buttonStyle(PrimaryPillStyle())
                }
                Button("Jump to 1,248") { count = 1_248 }.buttonStyle(GhostPillStyle())
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familiarCanvas()
        }
    }
    return Host()
}
