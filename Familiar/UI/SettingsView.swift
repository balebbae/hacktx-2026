import SwiftUI

/// Placeholder; S4 ships the full settings screen.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $state.userName).accessibilityHint("Used in the consent question")
                TextField("Place name", text: $state.placeName).accessibilityHint("Saved with each person you meet")
            }
            Section("Simulator") {
                Toggle("Speak cues aloud with the Apple voice", isOn: $state.speakLogSpeakerAloud)
            }
            Section("Keys") {
                row("ElevenLabs key", Secrets.elevenLabsAPIKey != nil)
                row("Meta Model API key", Secrets.metaModelAPIKey != nil)
                row("Modal endpoint", Secrets.modalEmbedURL != nil)
            }
        }
        .navigationTitle("Settings")
    }

    private func row(_ title: String, _ ok: Bool) -> some View {
        HStack { Text(title); Spacer(); Text(ok ? "present" : "missing").foregroundStyle(ok ? .green : .secondary) }
            .accessibilityElement(children: .combine)
    }
}
