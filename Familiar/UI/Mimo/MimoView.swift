import SwiftUI
import BotAvatarsKit
import ThinkingOrbsKit

/// What Mimo is doing. Driven by the app's authoritative state, never the other way round.
enum MimoState: Equatable {
    case idle, listening, thinking, speaking, cue, waitingForConsent, success, uncertain, paused, disconnected

    /// Plain-text twin of the animation, for VoiceOver and for the status line.
    var label: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .cue: return "Someone you know is nearby"
        case .waitingForConsent: return "Waiting for their choice"
        case .success: return "They chose to connect"
        case .uncertain: return "Not sure"
        case .paused: return "Awareness paused"
        case .disconnected: return "Camera not connected"
        }
    }

    var botState: BotAvatarState {
        switch self {
        case .thinking, .speaking, .cue, .success: return .working
        case .paused, .disconnected: return .sleeping
        case .idle, .listening, .waitingForConsent, .uncertain: return .default
        }
    }

    var speed: Double {
        switch self {
        case .listening: return 1.25
        case .uncertain, .waitingForConsent: return 0.7
        default: return 1
        }
    }

    /// The two states that earn the lumen ripple: an allowed cue, and a person choosing to connect.
    var earnsRipple: Bool { self == .cue || self == .success }
}

/// Mimo, the little lightkeeper: a mint `BotAvatar` from libraries.dev (Canvas-drawn, Reduce Motion aware) floating
/// over one soft lilac-to-mint glow. The orb grows with the vision profile (icon scale, capped at 1.2×) and, when a
/// cue or a consent lands, a single band of light ripples through it once. Decorative: VoiceOver reads
/// `MimoStatusLine` instead. The view's own frame is orb × 1.4 wide and orb × 1.2 tall; callers let it size itself.
struct MimoView: View {
    var state: MimoState = .idle
    var size: Double = 250
    var showsGlow: Bool = true

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var rippleProgress: CGFloat = 0
    @State private var rippleCount: Int = 0

    private var orbSize: Double { size * Double(min(1.2, scale.iconScale)) }
    private var stillPose: Bool { reduceMotion || scale.simplifyMotion || state == .paused }
    private var dimmed: Bool { state == .paused || state == .disconnected }

    var body: some View {
        ZStack {
            if showsGlow && !scale.highContrast && !reduceTransparency {
                MimoGlow(orbSize: orbSize, dimmed: dimmed)
            }
            BotAvatar(type: .blob,
                      face: .mouth,
                      state: state.botState,
                      size: orbSize,
                      color: BotColor("#75D9CF")!,
                      ink: BotColor("#172236")!,
                      saturation: 1.15,
                      speed: state.speed,
                      paused: stillPose,
                      interactive: !stillPose)
                .modifier(LumenRippleModifier(progress: rippleProgress, orbSize: orbSize, highContrast: scale.highContrast))
        }
        .frame(width: orbSize * 1.4, height: orbSize * 1.2)
        .accessibilityHidden(true)
        .onChange(of: state) { _, newState in
            guard newState.earnsRipple, !stillPose else { return }
            rippleCount += 1
        }
        .task(id: rippleCount) {
            guard rippleCount > 0 else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { rippleProgress = 0 }
            withAnimation(.easeOut(duration: 0.9)) { rippleProgress = 1 }
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withTransaction(still) { rippleProgress = 0 }
        }
    }
}

/// The soft two-pigment field under the orb. Never shown in high contrast or under Reduce Transparency.
private struct MimoGlow: View {
    let orbSize: Double
    let dimmed: Bool

    var body: some View {
        Ellipse()
            .fill(LinearGradient(colors: [FamiliarPalette.lilac.opacity(0.55), FamiliarPalette.mint.opacity(0.45)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: orbSize * 1.35, height: orbSize * 1.05)
            .blur(radius: orbSize * 0.22)
            .offset(y: orbSize * 0.08)
            .opacity(dimmed ? 0.35 : 1)
    }
}

/// Lumen ripple: one ring of light that expands from the orb's heart to its rim and fades as it goes. Animatable so
/// `withAnimation` drives `progress`; drawn in a Canvas clipped to the orb, so the light stays inside the body.
struct LumenRippleModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var orbSize: Double
    var highContrast: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay {
            LumenRippleRing(progress: progress, highContrast: highContrast)
                .frame(width: orbSize * 0.96, height: orbSize * 0.96)
                .clipShape(Circle())
                .blendMode(highContrast ? .normal : .plusLighter)
                .allowsHitTesting(false)
        }
    }
}

private struct LumenRippleRing: View {
    let progress: CGFloat
    let highContrast: Bool

    var body: some View {
        Canvas { context, size in
            guard progress > 0.001, progress < 0.999 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius: CGFloat = min(size.width, size.height) / 2
            let radius: CGFloat = maxRadius * (0.18 + 0.86 * progress)
            let fade: Double = Double(1 - progress)
            let width: CGFloat = (highContrast ? 5 : 3) + 12 * (1 - progress)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let ring = Path(ellipseIn: rect)
            context.opacity = fade * (highContrast ? 0.9 : 0.75)
            context.stroke(ring, with: .color(highContrast ? FamiliarPalette.inkHighContrast : Color.white), lineWidth: width)
            let inner = Path(ellipseIn: rect.insetBy(dx: width * 0.9, dy: width * 0.9))
            context.opacity = fade * 0.45
            context.stroke(inner, with: .color(FamiliarPalette.mint), lineWidth: max(1, width * 0.4))
        }
    }
}

/// The text twin of Mimo's state, with a tiny thinking orb while listening or thinking and a shimmer while thinking.
/// VoiceOver reads the text alone: the app name is the wake word, so it never goes through the speakers.
struct MimoStatusLine: View {
    let state: MimoState
    var text: String? = nil

    @Environment(\.visionScale) private var scale

    private var resolvedText: String { text ?? state.label }

    var body: some View {
        HStack(spacing: 8) {
            if state == .listening || state == .thinking {
                ThinkingOrb(state: state == .listening ? .listening : .working,
                            size: .px20,
                            paused: scale.simplifyMotion,
                            displaySize: 20 * Double(scale.iconScale))
                    .accessibilityHidden(true)
            }
            if state == .thinking && !scale.simplifyMotion {
                ShimmerText(resolvedText, font: FamiliarType.companion(scale), color: FamiliarPalette.inkSecondary(scale))
            } else {
                Text(resolvedText)
                    .font(FamiliarType.companion(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resolvedText)
    }
}

#Preview("Mimo states") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([MimoState.idle, .listening, .thinking, .cue, .paused], id: \.label) { (s: MimoState) in
                VStack(spacing: 6) {
                    MimoView(state: s, size: 160)
                    MimoStatusLine(state: s)
                }
            }
        }
        .padding(.vertical, 24)
    }
    .familiarCanvas()
}

#Preview("Mimo low vision") {
    VStack(spacing: 12) {
        MimoView(state: .cue, size: 200)
        MimoStatusLine(state: .cue, text: "Marcus, ahead, close.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .familiarCanvas()
    .environment(\.visionScale, VisionScale.make(.lowVision))
}
