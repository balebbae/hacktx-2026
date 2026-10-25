import SwiftUI

/// Full-screen card shown to the other person: the question in large rounded type, a waveform that moves while
/// the app listens, and two huge Yes / No targets. Tapping is the alternative to saying yes in a loud room.
struct ConsentCardView: View {
    let state: ConsentState
    let question: String
    let onAnswer: (Bool) -> Void
    let onCancel: () -> Void
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.familiarBody)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCard(radius: 16)
                    .accessibilityHint("Stops asking and saves nothing")
            }
            Spacer(minLength: 0)
            Image(systemName: state == .listening ? "waveform" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(FamiliarTheme.consent)
                .symbolEffect(.variableColor.iterative, isActive: state == .listening)
                .accessibilityHidden(true)
            Text(question)
                .font(.familiarHero)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(statusLine)
                .font(.familiarTitle)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(statusLine)")
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                answerButton("No", yes: false, color: FamiliarTheme.danger)
                answerButton("Yes", yes: true, color: FamiliarTheme.known)
            }
            .disabled(state == .saving)
            .sensoryFeedback(.impact(weight: .heavy), trigger: tapCount)
            Text("Your face stays on this phone. You can be removed any time.")
                .font(.familiarCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .familiarScreen()
    }

    private func answerButton(_ title: String, yes: Bool, color: Color) -> some View {
        Button {
            tapCount += 1
            onAnswer(yes)
        } label: {
            Text(title)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 150)
                .foregroundStyle(.black)
                .background(color, in: RoundedRectangle(cornerRadius: FamiliarTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(yes ? "Yes, remember me" : "No, do not remember me")
        .accessibilityHint(yes ? "Saves your face on this phone only" : "Nothing is saved")
    }

    private var statusLine: String {
        switch state {
        case .asking: return "Asking…"
        case .listening: return "Listening for your answer, or tap"
        case .saving: return "Saving…"
        default: return ""
        }
    }
}

#Preview {
    ConsentCardView(state: .listening, question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"), onAnswer: { _ in }, onCancel: {})
}
