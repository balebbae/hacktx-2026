import SwiftUI

/// Everyone who agreed. Tap for detail; swipe to remove (removal deletes record, thumbnail, consent clip, iOS contact).
struct PeopleView: View {
    @EnvironmentObject var runtime: FlowRuntime

    var body: some View {
        List {
            if runtime.people.isEmpty {
                Text("No one remembered yet.").foregroundStyle(.secondary)
                    .accessibilityLabel("No one remembered yet")
            }
            ForEach(runtime.people) { p in
                NavigationLink { PersonDetailView(person: p) } label: { row(p) }
                    .accessibilityHint("Shows details, call and text, and removal")
                    .swipeActions {
                        Button(role: .destructive) { runtime.remove(p) } label: { Label("Remove", systemImage: "trash") }
                            .accessibilityLabel("Remove \(p.name)")
                            .accessibilityHint("Deletes the face, consent clip and contact")
                    }
            }
        }
        .navigationTitle("People")
        .onAppear { runtime.refreshPeople() }
    }

    private func row(_ p: Person) -> some View {
        HStack(spacing: 12) {
            Thumb(image: runtime.thumbnail(for: p), name: p.name, size: 48)
            VStack(alignment: .leading) {
                Text(p.name).font(.headline)
                Text("met \(p.met.placeName.map { "at \($0), " } ?? "")\(p.met.at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Thumb: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Color(.secondarySystemFill); Text(String(name.prefix(1))).font(.system(size: size * 0.45, weight: .bold)) } }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityLabel(image == nil ? "No photo for \(name)" : "Photo of \(name)")
    }
}

struct PersonDetailView: View {
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.dismiss) private var dismiss
    @State var person: Person
    @State private var phone: String = ""
    @State private var confirmRemove = false
    @StateObject private var player = ClipPlayer()

    var body: some View {
        Form {
            Section {
                HStack { Spacer(); Thumb(image: runtime.thumbnail(for: person), name: person.name, size: 140); Spacer() }
                TextField("Name", text: $person.name, onCommit: save).font(.title2.weight(.semibold))
                    .accessibilityLabel("Name").accessibilityHint("Edit the name used in cues")
                TextField("Phone (optional)", text: $phone).keyboardType(.phonePad)
                    .accessibilityHint("Used for call and text, saved to the contact")
                    .onSubmit(save)
            }
            Section("Met") {
                LabeledContent("When", value: person.met.at.formatted(date: .long, time: .shortened))
                LabeledContent("Where", value: person.met.placeName ?? "unknown place")
                if let lat = person.met.latitude, let lon = person.met.longitude {
                    LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", lat, lon))
                }
                LabeledContent("Face samples", value: "\(person.embeddings.count)")
            }
            Section("Consent") {
                LabeledContent("How", value: person.consent.kind == .spoken ? "Spoken yes" : "Tapped YES")
                LabeledContent("Asked", value: person.consent.askedText)
                LabeledContent("Reply", value: person.consent.replyTranscript.isEmpty ? "–" : person.consent.replyTranscript)
                if let url = runtime.clipURL(for: person), FileManager.default.fileExists(atPath: url.path) {
                    Button { player.toggle(url) } label: { Label(player.isPlaying ? "Stop consent clip" : "Play consent clip", systemImage: player.isPlaying ? "stop.fill" : "play.fill") }
                        .accessibilityHint("Plays the few seconds of audio where they agreed")
                } else {
                    Text("No consent clip (Simulator or tapped).").foregroundStyle(.secondary)
                }
            }
            Section {
                Button { runtime.update(person); (runtime.router == nil ? nil : runtime.router)?.callDirect(person) } label: { Label("Call", systemImage: "phone") }
                    .disabled(cleanPhone == nil)
                    .accessibilityHint("Opens the phone dialer. Nothing is dialed automatically")
                Button { runtime.update(person); runtime.router?.textDirect(person) } label: { Label("Text", systemImage: "message") }
                    .disabled(cleanPhone == nil)
                    .accessibilityHint("Opens Messages. Nothing is sent automatically")
            }
            Section {
                Button(role: .destructive) { confirmRemove = true } label: { Label("Remove \(person.name)", systemImage: "trash") }
                    .accessibilityHint("Deletes the face data, thumbnail, consent clip and the contact this app created")
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { phone = person.phone ?? "" }
        .onDisappear { save(); player.stop() }
        .confirmationDialog("Remove \(person.name)? This deletes everything about them.", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove everything", role: .destructive) { runtime.remove(person); dismiss() }
            Button("Keep", role: .cancel) {}
        }
    }

    private var cleanPhone: String? { let t = phone.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
    private func save() {
        person.phone = cleanPhone
        if let stored = runtime.people.first(where: { $0.id == person.id }), stored != person { runtime.update(person) }
    }
}

import AVFoundation
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
