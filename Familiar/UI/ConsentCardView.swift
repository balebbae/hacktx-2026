import SwiftUI
import VoiceGlowKit

/// Full-screen card shown to the other person: Mimo waits respectfully, the question is in large type, and two huge
/// pills answer it. Tapping is the alternative to saying yes in a loud room. A soft glow at the bottom rises with the
/// microphone level while Familiar listens.
struct ConsentCardView: View {
    let state: ConsentState
    let question: String
    let onAnswer: (Bool) -> Void
    let onCancel: () -> Void
    var levelProvider: (() -> Double)? = nil
    @State private var tapCount = 0

    var body: some View {
        VoiceGlow(type: .mobile, levelProvider: levelProvider, active: state == .listening, colorVariant: .ocean, cornerRadius: 0) {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .buttonStyle(GhostPillStyle())
                        .frame(width: 110)
                        .accessibilityHint("Stops asking and saves nothing")
                }
                Spacer(minLength: 0)
                MimoView(state: state == .listening ? .listening : .waitingForConsent, size: 120, showsGlow: true)
                Text(question)
                    .font(FamiliarType.titleXL)
                    .foregroundStyle(FamiliarPalette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                MimoStatusLine(state: state == .listening ? .listening : .waitingForConsent, text: statusLine)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    Button { tapCount += 1; onAnswer(false) } label: { Text("No").frame(maxWidth: .infinity, minHeight: 110) }
                        .buttonStyle(GhostPillStyle())
                        .accessibilityLabel("No, do not remember me")
                        .accessibilityHint("Nothing is saved")
                    Button { tapCount += 1; onAnswer(true) } label: { Text("Yes").frame(maxWidth: .infinity, minHeight: 110) }
                        .buttonStyle(AccentPillStyle())
                        .accessibilityLabel("Yes, remember me")
                        .accessibilityHint("Saves your face on this phone only")
                }
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .disabled(state == .saving)
                .sensoryFeedback(.impact(weight: .medium), trigger: tapCount)
                Text("Your face stays on this phone. You can be removed any time.")
                    .font(FamiliarType.supporting)
                    .foregroundStyle(FamiliarPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .familiarCanvas()
    }

    private var statusLine: String {
        switch state {
        case .asking: return "Asking…"
        case .listening: return "Listening for your answer, or tap"
        case .saving: return "Saving…"
        default: return "Waiting"
        }
    }
}

#Preview {
    ConsentCardView(state: .listening, question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"), onAnswer: { _ in }, onCancel: {})
}
