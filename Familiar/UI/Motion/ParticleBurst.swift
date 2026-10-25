import SwiftUI

/// A short burst of dots and sparks (600 ms) every time `trigger` changes: the like-button moment, used when a
/// person taps Yes. Drawn in a `Canvas` from a deterministic seed, so no two bursts are identical and none is random
/// in a preview. Draws nothing under `simplifyMotion` or Reduce Motion, is never hit-testable and is hidden from
/// VoiceOver: the caller's text and haptic carry the meaning.
struct ParticleBurst: View {
    let trigger: Int
    let color: Color
    /// Overall size of the burst; the view itself has no intrinsic size and should be placed in an overlay.
    var radius: CGFloat = 64

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var generation: Int = 0

    static let duration: TimeInterval = 0.6

    init(trigger: Int, color: Color) {
        self.trigger = trigger
        self.color = color
    }

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: startedAt == nil)) { context in
            Canvas(rendersAsynchronously: false) { graphics, size in
                guard let startedAt else { return }
                let elapsed = context.date.timeIntervalSince(startedAt)
                guard elapsed >= 0, elapsed <= ParticleBurst.duration else { return }
                ParticleBurst.draw(in: &graphics,
                                   size: size,
                                   progress: elapsed / ParticleBurst.duration,
                                   seed: trigger,
                                   color: color,
                                   reach: radius * scale.iconScale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard animates else { return }
            generation += 1
            let expected = generation
            startedAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + ParticleBurst.duration + 0.1) {
                if expected == generation { startedAt = nil }
            }
        }
    }

    // MARK: Drawing

    private static let dotCount = 12
    private static let sparkCount = 6

    static func draw(in graphics: inout GraphicsContext, size: CGSize, progress: Double, seed: Int, color: Color, reach: CGFloat) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let eased = 1 - pow(1 - progress, 3)             // ease out: fast start, soft landing
        let fade = max(0, 1 - pow(progress, 1.6))

        for i in 0..<dotCount {
            let jitter = MotionNoise.unit(seed, i)
            let angle = (Double(i) / Double(dotCount)) * 2 * .pi + (jitter - 0.5) * 0.5
            let distance = reach * (0.3 + 0.7 * jitter) * eased
            let point = CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
            let dot = (3.2 + 2.8 * MotionNoise.unit(seed, i + 100)) * (1 - 0.6 * progress)
            let shade = MotionNoise.unit(seed, i + 200)
            let fill = shade < 0.35 ? color.opacity(0.65 * fade) : color.opacity(fade)
            graphics.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                          with: .color(fill))
        }

        for i in 0..<sparkCount {
            let jitter = MotionNoise.unit(seed, i + 300)
            let angle = (Double(i) / Double(sparkCount)) * 2 * .pi + .pi / Double(sparkCount) + (jitter - 0.5) * 0.4
            let distance = reach * (0.55 + 0.45 * jitter) * eased
            let length = 10.0 * (1 - progress) + 2
            let width = 2.4
            var spark = graphics
            spark.translateBy(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
            spark.rotate(by: Angle(radians: angle))
            let rect = CGRect(x: -length / 2, y: -width / 2, width: length, height: width)
            spark.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color.opacity(0.9 * fade)))
        }
    }
}

// MARK: - Previews

#Preview("Particle burst") {
    struct Host: View {
        @Environment(\.visionScale) private var scale
        @State private var bursts: Int = 0
        var body: some View {
            VStack(spacing: 32) {
                Button {
                    bursts += 1
                    FamiliarHaptics.play(.consent)
                } label: {
                    Label("Yes", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity, minHeight: 96)
                }
                .buttonStyle(AccentPillStyle())
                .overlay { ParticleBurst(trigger: bursts, color: FamiliarPalette.peach) }
                .accessibilityHint("Shows a burst of light")
                Text("Tap Yes. The burst lasts 600 ms and never shows under Reduce Motion.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .multilineTextAlignment(.center)
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familiarCanvas()
        }
    }
    return Host()
}
