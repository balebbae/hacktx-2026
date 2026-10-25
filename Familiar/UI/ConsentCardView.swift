import SwiftUI

/// Full-screen sheet shown to the other person: the question in large type and two large YES / NO buttons.
struct ConsentCardView: View {
    let state: ConsentState
    let question: String
    let onAnswer: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .accessibilityHint("Stops asking and saves nothing")
            }
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 56)).accessibilityHidden(true)
            Text(question)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(statusLine)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(statusLine)")
            Spacer()
            HStack(spacing: 16) {
                answerButton("NO", yes: false, color: .red)
                answerButton("YES", yes: true, color: .green)
            }
            .disabled(state == .saving)
            Text("Faces stay on this phone. You can be removed any time.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private func answerButton(_ title: String, yes: Bool, color: Color) -> some View {
        Button { onAnswer(yes) } label: {
            Text(title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .accessibilityLabel(yes ? "Yes, remember me" : "No, do not remember me")
        .accessibilityHint(yes ? "Saves your face on this phone only" : "Nothing is saved")
    }

    private var statusLine: String {
        switch state {
        case .asking: return "Asking…"
        case .listening: return "Listening for your answer… or tap"
        case .saving: return "Saving…"
        default: return ""
        }
    }
}

#Preview {
    ConsentCardView(state: .listening, question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"), onAnswer: { _ in }, onCancel: {})
}
