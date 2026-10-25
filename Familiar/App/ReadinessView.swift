import SwiftUI
import AVFoundation
import Speech
import Contacts
import CoreLocation

/// First-launch checklist: permissions, model file, keys and audio route. Shown by RootView while the coordinator
/// boots, as a sheet from the tab bar until it has been completed once, and from the Privacy page of onboarding.
struct ReadinessView: View {
    var onDone: (() -> Void)? = nil
    @StateObject private var model = ReadinessModel()
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var readyCount: Int { model.items.filter { $0.status == .ok }.count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summary
                    checklist
                    OnboardingTrustLine(text: "Nothing here records anything yet.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnboardingActionBar {
                Button { Task { await model.runAll() } } label: {
                    if model.running {
                        ShimmerText("Checking…", font: FamiliarType.control(scale), color: FamiliarPalette.canvas(scale), highlight: FamiliarPalette.lilac)
                    } else {
                        Label("Check everything", systemImage: "checklist")
                    }
                }
                .buttonStyle(PrimaryPillStyle())
                .disabled(model.running)
                .accessibilityLabel(model.running ? "Checking" : "Check everything")
                .accessibilityHint("Requests each permission in turn and checks the model and keys")
                if let onDone {
                    Button("Continue", action: onDone)
                        .buttonStyle(GhostPillStyle())
                        .accessibilityHint("Closes this checklist")
                }
            }
        }
        .familiarCanvas()
        .task { await model.check() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Setup")
            Text("Before we begin")
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Each row asks for one permission. You can skip any of them.")
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "5 of 8 ready", with the digits popping in as checks complete.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            NumberPop(value: readyCount, font: FamiliarType.display(scale), color: FamiliarPalette.ink(scale))
            Text("of \(model.items.count) ready")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(readyCount) of \(model.items.count) ready")
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                ReadinessRow(item: item)
                if index < model.items.count - 1 {
                    Divider()
                        .overlay(FamiliarPalette.stroke(scale))
                        .padding(.leading, dividerInset)   // lines up with the text column at every icon scale
                }
            }
        }
        .surfaceCard(padding: 6)
    }

    /// Row padding (12) + icon well (32 × iconScale) + row spacing (14); none in the stacked accessibility layout.
    private var dividerInset: CGFloat {
        typeSize.isAccessibilitySize ? 0 : 26 + 32 * scale.iconScale
    }
}

/// One permission or resource: status icon, title, detail and the status word in a chip. One VoiceOver element.
private struct ReadinessRow: View {
    let item: ReadinessModel.Item
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) { icon; chip }
                    text
                }
            } else {
                HStack(spacing: 14) {
                    icon
                    text
                    Spacer(minLength: 8)
                    chip
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(minHeight: scale.hitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title): \(item.status.word). \(item.detail)")
    }

    private var icon: some View {
        Image(systemName: item.status.symbol)
            .visionIcon(scale, base: 22)
            .foregroundStyle(item.status.color)
            .frame(width: 32 * scale.iconScale)
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
            Text(item.detail)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chip: some View {
        StatusChip(text: item.status.word, systemImage: item.status.symbol, tint: item.status.color)
            .contentTransition(.opacity)
    }
}

@MainActor
final class ReadinessModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status { case unknown, ok, missing, denied
        var symbol: String { switch self { case .unknown: return "circle"; case .ok: return "checkmark.circle.fill"; case .missing: return "exclamationmark.circle"; case .denied: return "xmark.circle.fill" } }
        var color: Color { switch self { case .unknown: return FamiliarPalette.inkSecondary; case .ok: return FamiliarPalette.success; case .missing: return FamiliarPalette.warning; case .denied: return FamiliarPalette.danger } }
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

#Preview("Readiness") {
    ReadinessView(onDone: {})
}
