import SwiftUI

/// Horizontal paging pager whose pages blur, fade and shrink into glass at the sides while you swipe.
///
/// Each child of `content` is one page and gets `.containerRelativeFrame(.horizontal)`. A page's `scrollTransition`
/// does the blur + fade + scale; on iOS 26 two edge strips of `.glassEffect(.regular, in: .rect)` fade in while the
/// scroll is moving (an `.ultraThinMaterial` strip before iOS 26). Under the vision profile's `simplifyMotion` or Reduce
/// Motion the pages only crossfade; under high contrast they keep their scale move but never blur or fade below 65 %,
/// and in all three cases (and under Reduce Transparency) no glass strips appear. Children keep their own identity, so an
/// outer `ScrollViewReader` can `scrollTo` a page by the `.id` the caller set.
struct GlassEdgePager<Content: View>: View {
    private let content: Content
    private let selection: Binding<Int?>?

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isScrolling: Bool = false

    /// Pages as children; swiping is the only navigation.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = nil
    }

    /// Pages as children plus a two-way page index, so a "Continue" button can set `selection` and the pager scrolls.
    init(selection: Binding<Int?>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = selection
    }

    /// Same, for a non-optional page index (`@State var page = 0`).
    init(selection: Binding<Int>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = Binding<Int?>(
            get: { selection.wrappedValue },
            set: { newValue in if let newValue { selection.wrappedValue = newValue } }
        )
    }

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }
    /// Blur and the deep fade: never for a high-contrast profile, whose ink stays opaque and sharp while swiping.
    private var softens: Bool { animates && !scale.highContrast }
    private var showsGlass: Bool { softens && !reduceTransparency }

    var body: some View {
        positioned
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, newPhase in
                let moving: Bool
                switch newPhase {
                case .idle: moving = false
                default: moving = true
                }
                if moving != isScrolling {
                    withAnimation(.easeInOut(duration: moving ? 0.18 : 0.4)) { isScrolling = moving }
                }
            }
            .overlay(alignment: .leading) { edgeStrip(.leading) }
            .overlay(alignment: .trailing) { edgeStrip(.trailing) }
    }

    /// The page binding is attached only when the caller asked for one, so pages without our `.id` keep their own.
    @ViewBuilder
    private var positioned: some View {
        if let selection {
            scrollView.scrollPosition(id: selection)
        } else {
            scrollView
        }
    }

    private var scrollView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        GlassEdgePage(animates: animates, softens: softens, index: index, tagsPages: selection != nil) {
                            subviews[index]
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
    }

    @ViewBuilder
    private func edgeStrip(_ edge: HorizontalEdge) -> some View {
        if showsGlass {
            GlassEdgeStrip(edge: edge, width: 34, visible: isScrolling)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// One page: full container width, blurred and faded as it leaves the centre (a light fade only when `softens` is
/// false, so high-contrast ink never dissolves).
private struct GlassEdgePage<Page: View>: View {
    let animates: Bool
    let softens: Bool
    let index: Int
    let tagsPages: Bool
    @ViewBuilder let page: () -> Page

    var body: some View {
        let framed = page()
            .containerRelativeFrame(.horizontal)
            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content
                    .opacity(1 - abs(phase.value) * (softens ? 0.55 : 0.35))
                    .blur(radius: softens ? abs(phase.value) * 14 : 0)
                    .scaleEffect(animates ? 1 - abs(phase.value) * 0.06 : 1)
            }
        if tagsPages {
            framed.id(index)
        } else {
            framed
        }
    }
}

/// A soft glass band on one side of the pager that only shows while the pages are moving.
private struct GlassEdgeStrip: View {
    let edge: HorizontalEdge
    let width: CGFloat
    let visible: Bool

    private var fade: LinearGradient {
        LinearGradient(colors: [Color.white, Color.white.opacity(0.6), Color.clear],
                       startPoint: edge == .leading ? .leading : .trailing,
                       endPoint: edge == .leading ? .trailing : .leading)
    }

    var body: some View {
        glass
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .mask { fade }
            .opacity(visible ? 1 : 0)
    }

    /// Liquid glass needs the iOS 26 SDK to type-check even behind `#available`, so the branch only exists for the
    /// Swift 6.2 compiler (Xcode 26); older toolchains build the material strip alone.
    @ViewBuilder
    private var glass: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular, in: .rect)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
        #else
        Rectangle().fill(.ultraThinMaterial)
        #endif
    }
}

/// Dots under a pager: the current page is a short ink pill. One VoiceOver element: "Page 2 of 5".
struct PagerIndicator: View {
    let count: Int
    let index: Int
    var tint: Color = FamiliarPalette.ink

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6 * scale.iconScale) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                Capsule()
                    .fill(i == index ? tint : tint.opacity(scale.highContrast ? 0.45 : 0.22))
                    .frame(width: (i == index ? 22 : 7) * scale.iconScale, height: 7 * scale.iconScale)
            }
        }
        .animation(FamiliarMotion.reduced(FamiliarMotion.animates(scale, reduceMotion: reduceMotion)), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

// MARK: - Previews

private struct GlassEdgePagerPreviewPage: View {
    let title: String
    let line: String
    let tint: Color
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(LinearGradient(colors: [tint, FamiliarPalette.lilac], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 140 * scale.iconScale, height: 140 * scale.iconScale)
                .accessibilityHidden(true)
            Text(title).font(FamiliarType.titleXL(scale)).foregroundStyle(FamiliarPalette.ink(scale))
            Text(line).font(FamiliarType.body(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale)).multilineTextAlignment(.center)
        }
        .padding(FamiliarPalette.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Glass edge pager") {
    VStack(spacing: 16) {
        GlassEdgePager {
            GlassEdgePagerPreviewPage(title: "Familiar", line: "Because everyone deserves to feel seen.", tint: FamiliarPalette.ocean)
            GlassEdgePagerPreviewPage(title: "Only people who said yes", line: "A stranger is simply a person.", tint: FamiliarPalette.mint)
            GlassEdgePagerPreviewPage(title: "Felt, not seen", line: "The finer things in life are felt, not seen.", tint: FamiliarPalette.peach)
        }
        PagerIndicator(count: 3, index: 0)
            .padding(.bottom, 24)
    }
    .familiarCanvas()
}

#Preview("Pager with selection") {
    struct Host: View {
        @State private var page: Int? = 0
        var body: some View {
            VStack(spacing: 16) {
                GlassEdgePager(selection: $page) {
                    GlassEdgePagerPreviewPage(title: "One", line: "Swipe or tap Continue.", tint: FamiliarPalette.ocean)
                    GlassEdgePagerPreviewPage(title: "Two", line: "Pages blur into glass at the edges.", tint: FamiliarPalette.lilac)
                    GlassEdgePagerPreviewPage(title: "Three", line: "Reduce Motion keeps only the crossfade.", tint: FamiliarPalette.mint)
                }
                PagerIndicator(count: 3, index: page ?? 0)
                Button("Continue") {
                    withAnimation(FamiliarMotion.spring) { page = min((page ?? 0) + 1, 2) }
                }
                .buttonStyle(PrimaryPillStyle())
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.bottom, 24)
            }
            .familiarCanvas()
        }
    }
    return Host()
}
