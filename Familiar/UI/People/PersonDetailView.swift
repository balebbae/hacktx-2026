import SwiftUI
import UIKit
import AVFoundation

/// One person who said yes: a large photo or monogram over a soft aurora halo, the name (editable), where and
/// when you met, four ghost pills (Call, Text, Where we met, Remove), the consent record and exactly what is stored.
/// Same `FlowRuntime` calls as before: `thumbnail(for:)`, `clipURL(for:)`, `update`, `remove`, `router?.callDirect/textDirect`.
struct PersonDetailView: View {
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State var person: Person
    @State private var phone: String = ""
    @State private var confirmRemove = false
    @State private var nameShake = 0
    @StateObject private var player = ClipPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PersonHero(image: runtime.thumbnail(for: person),
                           name: $person.name,
                           metLine: person.metLine,
                           consentKind: person.consentKindText,
                           consentSymbol: person.consentKindSymbol,
                           shake: nameShake,
                           onCommit: commitName)
                actionGrid
                contactCard
                consentCard
                storedCard
                Text("\(person.name) can ask to be removed at any time, and you can remove them here. Removing deletes the face data, thumbnail, consent clip and the contact this app created.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .padding(.horizontal, 4)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { phone = person.phone ?? "" }
        .onDisappear { save(); player.stop() }
        .confirmationDialog(Text("Remove \(person.name)? This deletes everything about them."), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove \(person.name)", role: .destructive) { removeEverything() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The face data, thumbnail, consent clip and the contact this app created are deleted from this phone.")
        }
    }

    // MARK: - Actions (2 x 2 ghost pills; one column at accessibility sizes)

    private var singleColumn: Bool { typeSize.isAccessibilitySize || scale.prefersStackedLayout }

    private var gridColumns: [GridItem] {
        singleColumn ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var actionGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            Button { call() } label: { Label("Call", systemImage: "phone") }
                .buttonStyle(GhostPillStyle())
                .disabled(cleanPhone == nil)
                .accessibilityHint(cleanPhone == nil ? "Add a phone number below first" : "Opens the phone dialer. Nothing is dialed automatically")
            Button { text() } label: { Label("Text", systemImage: "message") }
                .buttonStyle(GhostPillStyle())
                .disabled(cleanPhone == nil)
                .accessibilityHint(cleanPhone == nil ? "Add a phone number below first" : "Opens Messages. Nothing is sent automatically")
            NavigationLink { PlacesMapView(people: runtime.people, focus: person) } label: { Label("Where we met", systemImage: "map") }
                .buttonStyle(GhostPillStyle())
                .accessibilityHint("Shows the place on a map, with the other people you met")
            Button(role: .destructive) { confirmRemove = true } label: { Label("Remove", systemImage: "trash") }
                .buttonStyle(RemovePillStyle())
                .accessibilityLabel("Remove \(person.name)")
                .accessibilityHint("Asks first, then deletes the face data, thumbnail, consent clip and the contact this app created")
        }
    }

    // MARK: - Cards

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Contact")
            TextField("Phone (optional)", text: $phone)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .keyboardType(.phonePad)
                .onSubmit(save)
                .accessibilityHint("Used for call and text, saved to the contact")
            Text("Call and text open the dialer or Messages. Nothing is dialed or sent for you.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Consent")
            ConsentField(label: "How", value: person.consentKindText)
            ConsentField(label: "Agreed on", value: person.consent.at.formatted(date: .long, time: .shortened))
            ConsentField(label: "Asked", value: person.consent.askedText)
            ConsentField(label: "Reply", value: person.consent.replyTranscript.isEmpty ? "Tapped, no words recorded" : "“\(person.consent.replyTranscript)”")
            clipControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    @ViewBuilder
    private var clipControl: some View {
        if let url = runtime.clipURL(for: person), FileManager.default.fileExists(atPath: url.path) {
            Button { player.toggle(url) } label: {
                Label(player.isPlaying ? "Stop consent clip" : "Play consent clip", systemImage: player.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(GhostPillStyle())
            .accessibilityHint("Plays the few seconds of audio where they agreed. It never leaves this phone")
        } else {
            Text("No consent clip saved. They tapped yes, or this phone could not record.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
    }

    private var storedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Stored on this phone")
            StoredFactLine(symbol: "textformat", text: "Name: \(person.name)")
            StoredFactLine(symbol: "phone", text: cleanPhone.map { "Phone: \($0)" } ?? "No phone number")
            StoredFactLine(symbol: "faceid", text: person.embeddings.count == 1 ? "1 face sample" : "\(person.embeddings.count) face samples")
            StoredFactLine(symbol: "checkmark.seal", text: "Their yes, with the question that was asked")
            StoredFactLine(symbol: "mappin.and.ellipse", text: metFactText)
            StoredFactLine(symbol: "person.crop.rectangle", text: person.contactIdentifier == nil ? "No contact card yet" : "A contact card this app created")
            Text("Nothing else. No conversations, no mood, no history of where they were.")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    /// "Met October 24, 2026 at 10:00 AM at HackTX", or without a confirmed place, "…, place not saved".
    private var metFactText: String {
        if let place = person.met.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            return "Met \(person.metLongText) at \(place)"
        }
        return "Met \(person.metLongText), place not saved"
    }

    // MARK: - Behaviour (unchanged runtime calls)

    private var cleanPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The stored name, for restoring a cleared field. A person needs a name for cues.
    private var storedName: String? {
        runtime.people.first(where: { $0.id == person.id })?.name
    }

    private func commitName() {
        let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Shake (the modifier plays the error haptic) and restore the stored name.
            nameShake += 1
            person.name = storedName ?? person.name
            return
        }
        person.name = trimmed
        save()
    }

    /// Writes the record back only when something changed. A blank name is never persisted: it is restored from
    /// the store first, so every cue keeps a real name.
    private func save() {
        let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            person.name = storedName ?? person.name
        } else {
            person.name = trimmed
        }
        person.phone = cleanPhone
        if let stored = runtime.people.first(where: { $0.id == person.id }), stored != person { runtime.update(person) }
    }

    private func call() {
        save()
        runtime.router?.callDirect(person)
    }

    private func text() {
        save()
        runtime.router?.textDirect(person)
    }

    private func removeEverything() {
        player.stop()
        runtime.remove(person)
        FamiliarHaptics.play(.accepted)
        UIAccessibility.post(notification: .announcement, argument: "Removed \(person.name). Everything about them was deleted from this phone.")
        dismiss()
    }
}

// MARK: - Hero

/// Large photo or monogram over a soft aurora halo, the editable name, the met line and two chips.
private struct PersonHero: View {
    let image: UIImage?
    @Binding var name: String
    let metLine: String
    let consentKind: String
    let consentSymbol: String
    let shake: Int
    let onCommit: () -> Void
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 12) {
            portrait
                .padding(.top, 8)
            VStack(spacing: 4) {
                TextField("Name", text: $name)
                    .font(FamiliarType.titleXL(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(onCommit)
                    .errorShake(trigger: shake)
                    .accessibilityLabel("Name")
                    .accessibilityHint("Edit the name used in cues. Return saves it")
                Text("Tap the name to edit it")
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .accessibilityHidden(true)
            }
            Text(metLine)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                StatusChip(text: "Opted in", systemImage: "checkmark.seal.fill", tint: FamiliarPalette.success)
                StatusChip(text: consentKind, systemImage: consentSymbol, tint: FamiliarPalette.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }

    /// The halo and the portrait scale once, with the icon scale (`Thumb` and `Monogram` scale themselves).
    private var haloSide: CGFloat { scale.icon(230) }

    private var portrait: some View {
        ZStack {
            if !scale.highContrast {
                AuroraBackground(intensity: 0.7, mood: .calm)
                    .frame(width: haloSide, height: haloSide)
                    .mask { Circle() }
                    .blur(radius: 30)
                    .opacity(0.75)
                    .accessibilityHidden(true)
            }
            Thumb(image: image, name: name, size: 148)
        }
        .frame(height: haloSide)
    }
}

/// A label above a value; one VoiceOver element reading "Label, value".
private struct ConsentField: View {
    let label: String
    let value: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text(value)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// One line of "what is stored": an icon and a sentence.
private struct StoredFactLine: View {
    let symbol: String
    let text: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .visionIcon(scale, base: 16)
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .frame(width: scale.icon(24))
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A ghost pill whose words and hairline are the danger colour: the one removal control on the screen. Same
/// chrome as `GhostPillStyle` (control font, profile padding and hit target, capsule hit area, gated squeeze).
private struct RemovePillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.control(scale))
            .foregroundStyle(FamiliarPalette.danger)
            .multilineTextAlignment(.center)
            .padding(.horizontal, scale.spacing(24))
            .padding(.vertical, scale.spacing(12))
            .frame(maxWidth: .infinity, minHeight: scale.hitTarget)
            .background(FamiliarPalette.surface(scale), in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.danger.opacity(scale.highContrast ? 1 : 0.5), lineWidth: scale.strokeWidth))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && FamiliarMotion.animates(scale, reduceMotion: reduceMotion) ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

// MARK: - Thumb

/// A person's photo in a soft squircle, or their monogram when there is no photo. `size` is the balanced base
/// size; the profile's icon scale is applied once here (and once inside `Monogram`, which takes the base).
struct Thumb: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    @Environment(\.visionScale) private var scale

    private var side: CGFloat { scale.icon(size) }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous).strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
                .accessibilityLabel("Photo of \(name)")
        } else {
            Monogram(name: name, size: size)
        }
    }
}

// MARK: - Clip player

/// Plays the few seconds of audio where they agreed. Local file only.
@MainActor
final class ClipPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    func toggle(_ url: URL) { isPlaying ? stop() : play(url) }
    func play(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url); player?.delegate = self; player?.play(); isPlaying = player?.isPlaying ?? false
    }
    func stop() { player?.stop(); player = nil; isPlaying = false }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.isPlaying = false } }
}

// MARK: - Previews

#Preview("Person detail") {
    NavigationStack { PersonDetailView(person: PeoplePreviewData.marcus) }
        .environmentObject(FlowRuntime())
}

#Preview("Person detail, no phone") {
    NavigationStack { PersonDetailView(person: PeoplePreviewData.maya) }
        .environmentObject(FlowRuntime())
}
