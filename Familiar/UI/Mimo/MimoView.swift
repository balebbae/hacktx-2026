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
        case .disconnected: return "Glasses disconnected"
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
}

/// Mimo, the little lightkeeper: a mint `BotAvatar` from libraries.dev (Canvas-drawn, Reduce Motion aware) floating
/// over one soft lilac-to-mint glow. Decorative: VoiceOver reads `MimoStatusLine` instead.
struct MimoView: View {
    var state: MimoState = .idle
    var size: Double = 250
    var showsGlow: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showsGlow {
                Ellipse()
                    .fill(LinearGradient(colors: [FamiliarPalette.lilac.opacity(0.55), FamiliarPalette.mint.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 1.35, height: size * 1.05)
                    .blur(radius: size * 0.22)
                    .offset(y: size * 0.08)
                    .opacity(state == .paused || state == .disconnected ? 0.35 : 1)
            }
            BotAvatar(type: .blob,
                      face: .mouth,
                      state: state.botState,
                      size: size,
                      color: BotColor("#75D9CF")!,
                      ink: BotColor("#172236")!,
                      saturation: 1.15,
                      speed: state.speed,
                      paused: reduceMotion || state == .paused,
                      interactive: true)
        }
        .frame(width: size * 1.4, height: size * 1.2)
        .accessibilityHidden(true)
    }
}

/// The text twin of Mimo's state, with a tiny thinking orb while listening or thinking.
struct MimoStatusLine: View {
    let state: MimoState
    var text: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if state == .listening || state == .thinking {
                ThinkingOrb(state: state == .listening ? .listening : .working, size: .px20, displaySize: 20)
                    .accessibilityHidden(true)
            }
            Text(text ?? state.label)
                .font(FamiliarType.companion)
                .foregroundStyle(FamiliarPalette.inkSecondary)
        }
        .accessibilityLabel("Familiar: \(text ?? state.label)")
    }
}

#Preview("Mimo states") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([MimoState.idle, .listening, .thinking, .paused], id: \.label) { s in
                VStack { MimoView(state: s, size: 160); MimoStatusLine(state: s) }
            }
        }
    }
    .familiarCanvas()
}
