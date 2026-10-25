import SwiftUI

/// Placeholder until S4 ships the real permission / asset checklist. The coordinator marks the app ready immediately.
struct ReadinessView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Getting ready…").font(.title3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Getting ready")
    }
}
