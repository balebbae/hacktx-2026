import SwiftUI

// MARK: - Public surface

extension View {
    /// Shakes the view sideways once each time `trigger` changes and plays the error haptic. No movement under
    /// `simplifyMotion` / Reduce Motion (the haptic and the caller's text still say what went wrong).
    func errorShake(trigger: Int) -> some View {
        modifier(ErrorShake(trigger: trigger))
    }

    /// Shows the view as a soft shimmering skeleton (`.redacted(.placeholder)`) until `isLoaded`, then resolves it
    /// from a slight blur into the real content. While loading the content is hidden from VoiceOver and a single
    /// "Loading" element stands in for it; hit testing is off until the content is real.
    func skeletonReveal(isLoaded: Bool) -> some View {
        modifier(SkeletonReveal(isLoaded: isLoaded))
    }

    /// Tap feedback for cards and rows: 0.97 scale for 100 ms on touch down (spec §3.4), once per touch. Coexists
    /// with buttons and scrolling; nothing moves under `simplifyMotion` / Reduce Motion.
    func liftOnPress() -> some View {
        modifier(LiftOnPress())
    }

    /// Animates size changes of a card whose content changes (a line of text appears, a row is added) with the
    /// Familiar spring, as one geometry group. Changes that already carry an animation, that disable animation, or
    /// that come from a continuous gesture keep their own transaction. Nothing is animated under `simplifyMotion` /
    /// Reduce Motion. Wrap text-and-row cards only: do not wrap sliders, text fields or kit views that animate
    /// themselves, because every other unanimated change inside the card gets the spring too.
    func cardResize() -> some View {
        modifier(CardResize())
    }

    /// A gentle 3D tilt that follows the finger while it drags on the view, springing flat on release. For the
    /// Today hero card. Off under `simplifyMotion` / Reduce Motion.
    func tilt3D(maxDegrees: Double = 7) -> some View {
        modifier(Tilt3D(maxDegrees: maxDegrees))
    }
}

// MARK: - Error shake

private struct ErrorShake: ViewModifier {
    let trigger: Int
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var amplitude: Double { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) ? 1 : 0 }

    /// Sideways offsets the view steps through, then back to 0 (the first phase).
    private static let phases: [Double] = [0, -9, 8, -6, 4]

    func body(content: Content) -> some View {
        content
            .phaseAnimator(ErrorShake.phases, trigger: trigger) { view, offset in
                view.offset(x: offset * amplitude)
            } animation: { offset in
                offset == 0 ? Animation.easeOut(duration: 0.1) : Animation.linear(duration: 0.07)
            }
            .onChange(of: trigger) { _, _ in FamiliarHaptics.play(.error) }
    }
}

// MARK: - Skeleton reveal

private struct SkeletonReveal: ViewModifier {
    let isLoaded: Bool
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    /// Only the content is hidden from VoiceOver while loading; the "Loading" overlay below stays exposed.
    func body(content: Content) -> some View {
        content
            .accessibilityHidden(!isLoaded)
            .redacted(reason: isLoaded ? RedactionReasons() : .placeholder)
            .opacity(isLoaded ? 1 : 0.75)
            .blur(radius: isLoaded || !animates ? 0 : 2.5)
            .overlay { if !isLoaded && animates { SkeletonSheen() } }
            .overlay { if !isLoaded { loadingElement } }
            .animation(animates ? FamiliarMotion.diffusion : nil, value: isLoaded)
            .allowsHitTesting(isLoaded)
    }

    private var loadingElement: some View {
        Color.clear
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// A pale diagonal band crossing the skeleton every 1.6 s.
private struct SkeletonSheen: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = ShimmerText.progress(at: context.date, period: 1.6)
            let x = -0.6 + progress * 2.2
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55), Color.white.opacity(0)],
                           startPoint: UnitPoint(x: x - 0.35, y: 0),
                           endPoint: UnitPoint(x: x + 0.35, y: 1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lift on press

private struct LiftOnPress: ViewModifier {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed: Bool = false
    /// Start point of the touch currently being tracked, so a finger that keeps moving squeezes the card once, not
    /// every 100 ms. A new touch has a new start point even when the previous gesture was cancelled by a scroll.
    @State private var activeStart: CGPoint? = nil
    @State private var generation: Int = 0

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && animates ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in lift(from: value.startLocation) }
                    .onEnded { _ in release() },
                including: animates ? .all : .none
            )
    }

    private func lift(from start: CGPoint) {
        if activeStart == start { return }
        activeStart = start
        pressed = true
        generation += 1
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if expected == generation { pressed = false }
        }
    }

    private func release() {
        activeStart = nil
        pressed = false
    }
}

// MARK: - Card resize

private struct CardResize: ViewModifier {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                guard animates,
                      transaction.animation == nil,
                      !transaction.disablesAnimations,
                      !transaction.isContinuous else { return }
                transaction.animation = FamiliarMotion.spring
            }
            .geometryGroup()
    }
}

// MARK: - 3D tilt

private struct Tilt3D: ViewModifier {
    let maxDegrees: Double
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(-tilt.height) * maxDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(Double(tilt.width) * maxDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        let w = Tilt3D.clamp(value.translation.width / 140)
                        let h = Tilt3D.clamp(value.translation.height / 140)
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                            tilt = CGSize(width: w, height: h)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(FamiliarMotion.settle) { tilt = .zero }
                    },
                including: animates ? .all : .none
            )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(-1, value))
    }
}

// MARK: - Previews

private struct MotionModifiersPreview: View {
    @Environment(\.visionScale) private var scale
    @State private var shakes: Int = 0
    @State private var isLoaded: Bool = false
    @State private var expanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Marcus").font(FamiliarType.title(scale)).foregroundStyle(FamiliarPalette.ink(scale))
                    Text("Met at HackTX, UT Austin. Opted in.").font(FamiliarType.supporting(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
                .skeletonReveal(isLoaded: isLoaded)
                Button(isLoaded ? "Show skeleton" : "Load") { isLoaded.toggle() }
                    .buttonStyle(GhostPillStyle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("Only people who said yes").font(FamiliarType.title(scale)).foregroundStyle(FamiliarPalette.ink(scale))
                    if expanded {
                        Text("A stranger is simply a person. Nothing about them is stored, described or sent anywhere.")
                            .font(FamiliarType.body(scale))
                            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
                .cardResize()
                .liftOnPress()
                .tilt3D()
                .onTapGesture { expanded.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows or hides the detail")

                Button("I don't know anyone called that") { shakes += 1 }
                    .buttonStyle(PrimaryPillStyle())
                    .errorShake(trigger: shakes)
            }
            .padding(FamiliarPalette.margin)
        }
        .familiarCanvas()
    }
}

#Preview("Motion modifiers") {
    MotionModifiersPreview()
}

#Preview("Motion modifiers · non-visual profile") {
    MotionModifiersPreview()
        .environment(\.visionScale, VisionScale.make(.nonVisual))
}
