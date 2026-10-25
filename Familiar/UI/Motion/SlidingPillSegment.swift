import SwiftUI

/// Segmented control drawn as pills: the ink indicator slides under the selected option with
/// `matchedGeometryEffect` (a plain crossfade under `simplifyMotion` / Reduce Motion). Every option is a real button
/// with the `isSelected` trait, the platform convention for segments, so VoiceOver, Voice Control and Switch Control
/// all work; the container also carries the current choice as its value. Options sit side by side on the balanced
/// design and stack into rows at accessibility Dynamic Type sizes or when the profile prefers stacked layouts, so a
/// label never breaks mid-word. Height follows the vision profile's hit target.
struct SlidingPillSegment<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    /// Spoken name of the whole control ("Cue level"). Falls back to "Options".
    var label: String = "Options"

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pill

    init(options: [(T, String)], selection: Binding<T>) {
        self.options = options
        self._selection = selection
    }

    init(options: [(T, String)], selection: Binding<T>, label: String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }
    private var padding: CGFloat { scale.highContrast ? 3 : 4 }
    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout }
    private var trackColor: Color { scale.highContrast ? FamiliarPalette.surface : FamiliarPalette.canvasSecondary }
    private var selectedTitle: String { options.first(where: { $0.0 == selection })?.1 ?? "" }

    /// A capsule around one row; the same radius as rounded corners when the options stack.
    private var track: RoundedRectangle {
        RoundedRectangle(cornerRadius: scale.hitTarget / 2, style: stacked ? .continuous : .circular)
    }

    var body: some View {
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(spacing: padding))
            : AnyLayout(HStackLayout(spacing: padding))
        return layout {
            ForEach(options.indices, id: \.self) { index in
                segment(at: index)
            }
        }
        .padding(padding)
        .background(trackColor, in: track)
        .overlay(track.strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.highContrast ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(selectedTitle)
    }

    private func segment(at index: Int) -> some View {
        let value = options[index].0
        let title = options[index].1
        let isSelected = value == selection
        return Button {
            select(value)
        } label: {
            Text(title)
                .font(FamiliarType.control(scale))
                .foregroundStyle(isSelected ? FamiliarPalette.canvas(scale) : FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: scale.hitTarget - padding * 2)
                .background { indicator(isSelected: isSelected) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint(isSelected ? "" : "Selects \(title)")
    }

    /// The ink pill under the selected option. It is matched across segments only while motion is allowed; under
    /// reduced motion each pill is its own view and simply crossfades, so nothing slides.
    @ViewBuilder
    private func indicator(isSelected: Bool) -> some View {
        if isSelected {
            if animates {
                Capsule()
                    .fill(FamiliarPalette.ink(scale))
                    .matchedGeometryEffect(id: "indicator", in: pill)
            } else {
                Capsule()
                    .fill(FamiliarPalette.ink(scale))
                    .transition(.opacity)
            }
        }
    }

    private func select(_ value: T) {
        guard value != selection else { return }
        withAnimation(FamiliarMotion.reduced(animates)) { selection = value }
        FamiliarHaptics.play(.accepted)
    }
}

// MARK: - Previews

#Preview("Sliding pill segment") {
    struct Host: View {
        enum Level: Hashable { case quiet, normal, chatty }
        @Environment(\.visionScale) private var scale
        @State private var level: Level = .normal
        @State private var filter: String = "All"
        var body: some View {
            VStack(spacing: 24) {
                SlidingPillSegment(options: [(Level.quiet, "Quiet"), (Level.normal, "Normal"), (Level.chatty, "Chatty")],
                                   selection: $level,
                                   label: "Cue level")
                SlidingPillSegment(options: [("All", "All"), ("Recent", "Recent")], selection: $filter, label: "People filter")
                    .frame(width: 220)
                Text("Quiet says less, chatty says more.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familiarCanvas()
        }
    }
    return Host()
}

#Preview("Sliding pill segment · severe (stacked)") {
    struct Host: View {
        @State private var level: String = "Normal"
        var body: some View {
            SlidingPillSegment(options: [("Quiet", "Quiet"), ("Normal", "Normal"), ("Chatty", "Chatty")], selection: $level, label: "Cue level")
                .padding(FamiliarPalette.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .familiarCanvas()
                .environment(\.visionScale, VisionScale.make(.severe))
        }
    }
    return Host()
}

#Preview("Sliding pill segment · accessibility type") {
    struct Host: View {
        @State private var level: String = "Normal"
        var body: some View {
            SlidingPillSegment(options: [("Quiet", "Quiet"), ("Normal", "Normal"), ("Chatty", "Chatty")], selection: $level, label: "Cue level")
                .padding(FamiliarPalette.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .familiarCanvas()
                .environment(\.dynamicTypeSize, DynamicTypeSize.accessibility2)
        }
    }
    return Host()
}
