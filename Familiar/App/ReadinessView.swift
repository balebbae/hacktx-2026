import SwiftUI
import AVFoundation
import Speech
import Contacts
import CoreLocation

/// First-launch checklist: permissions, model file, keys and audio route. Also shown by RootView while the coordinator boots.
struct ReadinessView: View {
    var onDone: (() -> Void)? = nil
    @StateObject private var model = ReadinessModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Nothing here records anything yet. Each row asks for one permission; you can skip any of them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Permissions") {
                    ForEach(model.items) { item in
                        HStack {
                            Image(systemName: item.status.symbol).foregroundStyle(item.status.color).accessibilityHidden(true)
                            VStack(alignment: .leading) { Text(item.title); Text(item.detail).font(.footnote).foregroundStyle(.secondary) }
                            Spacer()
                            Text(item.status.word).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.title): \(item.status.word). \(item.detail)")
                    }
                }
                Section {
                    Button { Task { await model.runAll() } } label: { Label(model.running ? "Checking…" : "Check everything", systemImage: "checklist") }
                        .disabled(model.running)
                        .accessibilityHint("Requests each permission in turn and checks the model and keys")
                    if let onDone {
                        Button("Continue", action: onDone).font(.headline)
                            .accessibilityHint("Goes to the home screen")
                    }
                }
            }
            .navigationTitle("Ready?")
            .task { await model.check() }
        }
    }
}

@MainActor
final class ReadinessModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status { case unknown, ok, missing, denied
        var symbol: String { switch self { case .unknown: return "circle"; case .ok: return "checkmark.circle.fill"; case .missing: return "exclamationmark.circle"; case .denied: return "xmark.circle.fill" } }
        var color: Color { switch self { case .unknown: return .secondary; case .ok: return .green; case .missing: return .orange; case .denied: return .red } }
        var word: String { switch self { case .unknown: return "not checked"; case .ok: return "ready"; case .missing: return "missing"; case .denied: return "denied" } }
    }
    struct Item: Identifiable { let id: String; let title: String; let detail: String; var status: Status }

    @Published var items: [Item] = [
        Item(id: "camera", title: "Camera", detail: "Sees who is around you", status: .unknown),
        Item(id: "mic", title: "Microphone", detail: "Hears the wake word and the other person's yes", status: .unknown),
        Item(id: "speech", title: "Speech recognition", detail: "On-device transcript, 90 seconds in memory", status: .unknown),
        Item(id: "contacts", title: "Contacts", detail: "Creates a contact for each person who agrees", status: .unknown),
        Item(id: "location", title: "Location (once)", detail: "Remembers where you met someone", status: .unknown),
        Item(id: "model", title: "Face model", detail: "w600k_mbf.onnx in the app bundle", status: .unknown),
        Item(id: "keys", title: "Keys", detail: "ElevenLabs and Meta Model API", status: .unknown),
        Item(id: "route", title: "Audio route", detail: "Glasses or phone", status: .unknown),
    ]
    @Published var running = false
    private lazy var location = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Void, Never>?

    func check() async {
        set("camera", from: AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        set("mic", from: AVAudioApplication.shared.recordPermission == .granted)
        set("speech", from: SFSpeechRecognizer.authorizationStatus() == .authorized)
        set("contacts", from: CNContactStore.authorizationStatus(for: .contacts) == .authorized)
        set("location", from: [.authorizedWhenInUse, .authorizedAlways].contains(location.authorizationStatus))
        update("model", Bundle.main.url(forResource: "w600k_mbf", withExtension: "onnx") == nil ? .missing : .ok)
        update("keys", (Secrets.elevenLabsAPIKey != nil && Secrets.metaModelAPIKey != nil) ? .ok : .missing)
        update("route", AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP } ? .ok : .missing)
        items.first(where: { $0.id == "route" }).map { _ in }
        if let i = items.firstIndex(where: { $0.id == "route" }), items[i].status == .missing { items[i] = Item(id: "route", title: "Audio route", detail: "Phone only. Pair the glasses for the real thing", status: .missing) }
    }

    func runAll() async {
        running = true; defer { running = false }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVAudioApplication.requestRecordPermission()
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { _ in c.resume() } }
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        if location.authorizationStatus == .notDetermined {
            location.delegate = self
            await withCheckedContinuation { c in locationContinuation = c; location.requestWhenInUseAuthorization() }
        }
        await check()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            locationContinuation?.resume(); locationContinuation = nil
        }
    }

    private func set(_ id: String, from ok: Bool) { update(id, ok ? .ok : .denied) }
    private func update(_ id: String, _ s: Status) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = s } }
}
