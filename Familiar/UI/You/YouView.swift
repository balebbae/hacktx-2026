import SwiftUI

/// The You tab: who you are, how Familiar communicates, and the controls that keep your people yours.
struct YouView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.openReadiness) private var openReadiness
    @Environment(\.visionScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                YouProfileCard(name: state.userName, peopleCount: runtime.people.count, profile: state.visionProfile)
                preferences
                deviceAndData
                PrivacyBanner(text: JudgeView.banner)
                YouMottoFooter()
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.bottom, 12)
        }
        .familiarCanvas()
        .navigationTitle("You")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { runtime.refreshPeople() }
    }

    private var header: some View {
        Text("You")
            .font(FamiliarType.titleXL(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private var preferences: some View {
        YouSection(title: "Preferences") {
            NavigationLink {
                SettingsView()
            } label: {
                YouRow(title: "Voice and cues", systemImage: "speaker.wave.2", detail: "Quiet, normal or chatty · voice · recognition")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens Voice and cues")
            YouDivider()
            NavigationLink {
                AccessibilitySettingsView()
            } label: {
                YouRow(title: "Accessibility", systemImage: "accessibility", detail: "Vision profile, text size, haptics, speech")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens Accessibility")
        }
    }

    private var deviceAndData: some View {
        YouSection(title: "Device and data") {
            Button(action: openReadiness) {
                YouRow(title: "Device and permissions", systemImage: "checklist", detail: "Glasses, camera, microphone, contacts")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens the readiness checklist")
            YouDivider()
            NavigationLink {
                PrivacyDashboardView()
            } label: {
                YouRow(title: "Privacy", systemImage: "lock.shield", detail: "Your people. Your control.")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens the privacy dashboard")
            YouDivider()
            NavigationLink {
                DemoControlsView()
            } label: {
                YouRow(title: "Demo controls", systemImage: "wand.and.stars", detail: "Scripted helpers for the table")
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens the demo controls")
        }
    }
}

/// Who you are: an aurora band, your monogram, your name, how many people chose to connect, and your vision profile.
private struct YouProfileCard: View {
    let name: String
    let peopleCount: Int
    let profile: VisionProfile
    @Environment(\.visionScale) private var scale

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous) }
    /// `Monogram` scales its own `size` by the icon scale; this mirrors that for the band height, offset and padding.
    private var monogramSize: CGFloat { scale.icon(64) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                auroraBand
                    .frame(height: scale.icon(84))
                Monogram(name: name, size: 64)
                    .overlay(Circle().strokeBorder(FamiliarPalette.surface(scale), lineWidth: 3))
                    .padding(.leading, 20)
                    .offset(y: monogramSize / 2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                Text(YouCopy.peopleChoseToConnect(peopleCount))
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                StatusChip(text: profile.title, systemImage: "accessibility", tint: FamiliarPalette.ink(scale))
            }
            .padding(.horizontal, 20)
            .padding(.top, monogramSize / 2 + 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarPalette.surface(scale), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
        .shadow(color: Color.black.opacity(scale.shadowOpacity), radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(YouCopy.peopleChoseToConnect(peopleCount)). Vision profile \(profile.title).")
    }

    @ViewBuilder private var auroraBand: some View {
        if scale.highContrast {
            FamiliarPalette.canvasSecondary
        } else {
            AuroraBackground(intensity: 0.9, mood: .calm)
        }
    }
}

/// The motto, the tagline and the one-line trust promise.
private struct YouMottoFooter: View {
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 8) {
            Eyebrow(text: "Familiar")
            Text("The finer things in life are felt, not seen.")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
            Text("Because everyone deserves to feel seen.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
            Text("Faces and consent clips stay on this phone. Only text leaves it.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

#Preview("You") {
    NavigationStack {
        YouView()
            .environmentObject(AppState())
            .environmentObject(AppCoordinator())
            .environmentObject(FlowRuntime())
    }
}
