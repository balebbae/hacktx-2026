import SwiftUI

/// "Your people. Your control." — the counts, what is stored and where it goes, a map of where you met each person,
/// and the one button that removes everyone. Removal deletes the record, face samples, thumbnail, consent clip and
/// the contact this app created.
struct PrivacyDashboardView: View {
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmRemoveAll = false
    /// Consent clips found on disk, recounted when the people change (never in the render path).
    @State private var clipCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                counts
                stored
                leaves
                PrivacyBanner(text: JudgeView.banner)
                removeEveryone
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .youNavigationTitle("Privacy")
        .onAppear {
            runtime.refreshPeople()
            recountClips()
        }
        .onChange(of: runtime.people) { _, _ in recountClips() }
        .confirmationDialog(removeTitle, isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove \(YouCopy.people(peopleCount))", role: .destructive) { removeAll() }
            Button("Keep everyone", role: .cancel) {}
        } message: {
            Text("Deletes every record, face sample, thumbnail, consent clip and the contacts this app created. Nothing is kept.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your people. Your control.")
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
            Text("Everyone here said yes out loud or tapped yes. Anyone can be removed, and removing them deletes everything about them.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .padding(.horizontal, 4)
    }

    private var counts: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout
        let layout: AnyLayout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            PrivacyCountTile(value: peopleCount, label: peopleCount == 1 ? "remembered person" : "remembered people", systemImage: "person.2")
            PrivacyCountTile(value: clipCount, label: clipCount == 1 ? "consent clip" : "consent clips", systemImage: "waveform")
            PrivacyCountTile(value: contactCount, label: contactCount == 1 ? "contact created" : "contacts created", systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    private var stored: some View {
        YouSection(title: "What stays on this phone", footer: "Removing a person deletes all of it, including the contact.") {
            YouValueRow(title: "Face samples", value: "\(embeddingCount) in total", systemImage: "person.crop.square")
            YouDivider()
            YouValueRow(title: "Thumbnails", value: "one per person", systemImage: "photo")
            YouDivider()
            YouValueRow(title: "Consent clips", value: "a few seconds of audio", systemImage: "waveform")
            YouDivider()
            NavigationLink {
                PlacesMapView(people: runtime.people)
            } label: {
                YouRow(title: "Where and when you met", systemImage: "mappin.and.ellipse", detail: placesDetail)
            }
            .buttonStyle(YouRowButtonStyle())
            .accessibilityHint("Opens the map of where you met people")
            YouDivider()
            YouValueRow(title: "Contacts", value: "\(contactCount) created", systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    private var leaves: some View {
        YouSection(title: "What leaves the phone, as text", footer: modalFooter) {
            YouValueRow(title: "Cue sentences", value: "to the voice service", systemImage: "speaker.wave.2")
            YouDivider()
            YouValueRow(title: "Transcript snippets", value: "to find a name", systemImage: "text.quote")
            YouDivider()
            YouValueRow(title: "Face crops",
                        value: modalOn ? "112 px, Modal fallback on" : "never, Modal fallback off",
                        systemImage: "square.dashed",
                        tint: modalOn ? FamiliarPalette.warning : FamiliarPalette.inkSecondary(scale))
        }
    }

    private var removeEveryone: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) { confirmRemoveAll = true } label: {
                Label("Remove everyone", systemImage: "trash")
                    .foregroundStyle(peopleCount == 0 ? FamiliarPalette.inkSecondary(scale) : FamiliarPalette.danger)
            }
            .buttonStyle(GhostPillStyle())
            .disabled(peopleCount == 0)
            .accessibilityHint(peopleCount == 0 ? "No one is remembered yet" : "Asks before deleting \(YouCopy.people(peopleCount))")
            Text(peopleCount == 0 ? "No one is remembered yet." : "You will be asked to confirm. This cannot be undone.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Facts

    private var peopleCount: Int { runtime.people.count }

    private var embeddingCount: Int { runtime.people.reduce(0) { (sum: Int, p: Person) -> Int in sum + p.embeddings.count } }

    private var contactCount: Int { runtime.people.filter { (p: Person) -> Bool in p.contactIdentifier != nil }.count }

    private var placesDetail: String {
        peopleCount == 0 ? "A map of your people, once you have met someone" : "A map of \(YouCopy.people(peopleCount))"
    }

    /// Consent clips that exist on disk (tapped answers and the Simulator leave none).
    private func recountClips() {
        clipCount = runtime.people.filter { (p: Person) -> Bool in
            guard let url = runtime.clipURL(for: p) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }.count
    }

    /// The fallback is on whenever MODAL_EMBED_URL is set (`PerceptionPipeline` wraps the on-device embedder with it).
    private var modalOn: Bool { Secrets.modalEmbedURL != nil }

    private var modalFooter: String {
        if modalOn {
            return "The Modal fallback is on: aligned 112 by 112 face crops go to the embedding server and are discarded there. Remove MODAL_EMBED_URL from Secrets.xcconfig to turn it off."
        }
        return "Strangers are never named or stored. Cloud services only ever receive text."
    }

    private var removeTitle: String { YouCopy.removeEveryoneTitle(peopleCount) }

    private func removeAll() {
        runtime.resetPeople()
        FamiliarHaptics.play(.paused)
    }
}

/// A big number with a short label underneath. The digits pop in when the count changes.
private struct PrivacyCountTile: View {
    let value: Int
    let label: String
    let systemImage: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .visionIcon(scale, base: 18)
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .accessibilityHidden(true)
            NumberPop(value: value, font: FamiliarType.display(scale), color: FamiliarPalette.ink(scale))
            Text(label)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

#Preview("Privacy dashboard") {
    NavigationStack {
        PrivacyDashboardView()
            .environmentObject(FlowRuntime())
    }
}
