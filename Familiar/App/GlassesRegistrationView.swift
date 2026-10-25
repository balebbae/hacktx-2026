import CoreImage
import MWDATCore
import SwiftUI

/// Connect-the-glasses screen: Meta AI registration, camera permission, stream state and a
/// live preview. S5 links it from Settings; `--glasses` launch argument opens it at start.
struct GlassesRegistrationView: View {
    @StateObject private var model: GlassesRegistrationModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.visionScale) private var scale

    init(source: GlassesFrameSource? = nil) {
        _model = StateObject(wrappedValue: GlassesRegistrationModel(source: source))
    }

    var body: some View {
        List {
            Section("Glasses") {
                LabeledContent("Connection", value: model.registrationLabel)
                    .accessibilityLabel("Glasses connection: \(model.registrationLabel)")
                LabeledContent("Device", value: model.deviceLabel)
                    .accessibilityLabel("Device: \(model.deviceLabel)")
                if model.registration == .registered {
                    Button("Disconnect glasses", role: .destructive) { model.disconnect() }
                        .accessibilityHint("Removes this app from the Meta AI app")
                } else {
                    Button { model.connect() } label: {
                        Label("Connect glasses", systemImage: "eyeglasses")
                            .font(FamiliarType.control(scale))
                    }
                    .disabled(model.registration == .registering || model.registration == .unavailable)
                    .accessibilityHint("Opens the Meta AI app to approve this app. Developer Mode must be on.")
                }
            }
            Section("Camera") {
                LabeledContent("Permission", value: model.permissionLabel)
                    .accessibilityLabel("Glasses camera permission: \(model.permissionLabel)")
                if model.registration == .registered && model.permissionLabel == GlassesRegistrationModel.glassesNotLinked {
                    Text("Unfold the glasses and keep them near the phone. The Meta AI app must show them as connected.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if model.registration == .registered && model.permissionLabel != "Granted" {
                    Button("Allow glasses camera") { model.requestCameraPermission() }
                        .accessibilityHint("Asks the Meta AI app for camera access")
                }
                LabeledContent("Stream", value: model.status.label)
                    .accessibilityLabel("Stream: \(model.status.label)")
                if model.status == .streaming {
                    LabeledContent("Frames per second", value: String(format: "%.1f", model.fps))
                    LabeledContent("First frame after", value: model.firstFrameDelayLabel)
                }
                if model.status.isActive {
                    Button("Stop streaming", role: .destructive) { model.stopStreaming() }
                        .accessibilityHint("Stops the glasses camera")
                } else {
                    Button { model.startStreaming() } label: { Label("Start streaming", systemImage: "video") }
                        .disabled(model.registration != .registered)
                        .accessibilityHint("Starts the glasses camera over Bluetooth. The recording light turns on.")
                }
            }
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary).accessibilityLabel("Note: \(message)") }
            }
            Section("Preview") {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    if let image = model.preview {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Text(model.status == .waitingForFrames ? "Waiting for frames" : "No frames yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(model.preview == nil ? "No camera preview" : "Live glasses camera preview")
            }
            #if DEBUG
            Section("Simulator") {
                Button("Use mock glasses") { model.useMockGlasses() }
                    .accessibilityHint("Pairs a simulated pair of glasses that plays a bundled clip")
                Button("Fold mock glasses") { model.foldMockGlasses() }
                    .disabled(!GlassesMockDevice.isEnabled)
                    .accessibilityHint("Closes the simulated hinges; the stream should stop")
            }
            #endif
        }
        .navigationTitle("Glasses")
        .task { await model.observe() }
        // Back from the Meta AI app after "Allow" / "Always allow": re-read instead of showing the stale answer.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refreshPermission() } } }
        #if DEBUG
        .task {
            // `--glasses-mock` pairs the mock and streams immediately (Simulator demos, screenshots).
            guard ProcessInfo.processInfo.arguments.contains("--glasses-mock") else { return }
            model.useMockGlasses()
            try? await Task.sleep(for: .seconds(1))
            model.startStreaming()
        }
        #endif
    }
}

@MainActor
final class GlassesRegistrationModel: ObservableObject {
    @Published var registration: RegistrationState?
    @Published var permissionLabel = "Unknown"
    @Published var deviceLabel = "None"
    @Published var status: GlassesStatus = .idle
    @Published var fps: Double = 0
    @Published var preview: CGImage?
    @Published var message: String?
    @Published var firstFrameDelay: TimeInterval?

    let source: GlassesFrameSource
    private var startedAt: TimeInterval?
    private var lastPreviewAt: TimeInterval = 0
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(source: GlassesFrameSource? = nil) {
        self.source = source ?? GlassesFactory.makeFrameSource(options: .init())
        status = self.source.status
    }

    var registrationLabel: String {
        switch registration {
        case .none: return "Checking"
        case .unavailable: return "Meta AI app not installed"
        case .available: return "Not connected"
        case .registering: return "Approving in Meta AI"
        case .registered: return "Connected"
        @unknown default: return "Unknown"
        }
    }

    var firstFrameDelayLabel: String {
        guard let firstFrameDelay else { return "—" }
        return String(format: "%.1f s", firstFrameDelay)
    }

    func observe() async {
        guard GlassesSDK.configureIfNeeded() else {
            message = GlassesSDK.unavailableReason
            registration = .unavailable
            permissionLabel = "Unavailable"
            return
        }
        let wearables = Wearables.shared
        registration = wearables.registrationState
        await refreshPermission()
        updateDevices(wearables.devices)
        async let a: Void = observeRegistration(wearables)
        async let b: Void = observeDevices(wearables)
        async let c: Void = observeStatus()
        async let d: Void = observeFrames()
        _ = await (a, b, c, d)
    }

    private func observeRegistration(_ wearables: any WearablesInterface) async {
        for await state in wearables.registrationStateStream() {
            registration = state
            if state == .registered { await refreshPermission() }
        }
    }

    private func observeDevices(_ wearables: any WearablesInterface) async {
        for await ids in wearables.devicesStream() { updateDevices(ids) }
    }

    private func updateDevices(_ ids: [DeviceIdentifier]) {
        guard GlassesSDK.isConfigured, let id = ids.first else { deviceLabel = "None"; return }
        deviceLabel = Wearables.shared.deviceForIdentifier(id)?.nameOrId() ?? "Glasses"
    }

    private func observeStatus() async {
        for await s in source.statusChanges() {
            status = s
            if s == .streaming { permissionLabel = "Granted" }
            if s == .streaming, let startedAt, firstFrameDelay == nil {
                firstFrameDelay = CACurrentMediaTime() - startedAt
            }
            if case .stopped(let reason) = s { message = reason }
            if case .failed(let reason) = s { message = reason }
            if !s.isActive { fps = 0 }
        }
    }

    private func observeFrames() async {
        for await frame in source.subscribe() {
            let now = CACurrentMediaTime()
            guard now - lastPreviewAt > 0.1 else { continue }
            lastPreviewAt = now
            fps = source.framesPerSecond
            let ci = CIImage(cvPixelBuffer: frame.pixelBuffer)
            preview = ciContext.createCGImage(ci, from: ci.extent)
        }
    }

    /// The SDK only answers while a pair of glasses is linked ("if all devices disconnect, permissions become
    /// unavailable"), so a link drop must not wipe an earlier "Granted" and bring the Allow button back.
    func refreshPermission() async {
        guard GlassesSDK.isConfigured else { permissionLabel = "Unavailable"; return }
        guard registration == .registered else { permissionLabel = "Connect first"; return }
        if status == .streaming { permissionLabel = "Granted"; return }
        do {
            let s = try await Wearables.shared.checkPermissionStatus(.camera)
            permissionLabel = s == .granted ? "Granted" : "Not granted"
        } catch {
            if permissionLabel != "Granted" { permissionLabel = Self.glassesNotLinked }
            glassesLog.info("permission check: \(String(describing: error))")
        }
    }

    static let glassesNotLinked = "Glasses not linked"

    func connect() {
        guard GlassesSDK.isConfigured else { message = GlassesSDK.unavailableReason; return }
        message = nil
        Task {
            do { try await Wearables.shared.startRegistration() } catch {
                message = "Could not start: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        guard GlassesSDK.isConfigured else { message = GlassesSDK.unavailableReason; return }
        source.stop()
        Task {
            do { try await Wearables.shared.startUnregistration() } catch {
                message = "Could not disconnect: \(error.localizedDescription)"
            }
        }
    }

    func requestCameraPermission() {
        guard GlassesSDK.isConfigured else { message = GlassesSDK.unavailableReason; return }
        Task {
            do {
                let s = try await Wearables.shared.requestPermission(.camera)
                permissionLabel = s == .granted ? "Granted" : "Not granted"
            } catch {
                message = "Permission request failed: \(error.localizedDescription)"
            }
        }
    }

    func startStreaming() {
        message = nil
        firstFrameDelay = nil
        startedAt = CACurrentMediaTime()
        status = .connecting
        Task {
            do { try await source.start() } catch {
                message = error.localizedDescription
                status = source.status
            }
        }
    }

    func stopStreaming() {
        source.stop()
        preview = nil
    }

    #if DEBUG
    func useMockGlasses() {
        do {
            _ = try GlassesMockDevice.enable()
            message = "Mock glasses paired; playing \(GlassesMockDevice.defaultFixture).mov"
            registration = Wearables.shared.registrationState
            Task { await refreshPermission() }
        } catch {
            message = "Mock failed: \(error.localizedDescription)"
        }
    }

    func foldMockGlasses() { GlassesMockDevice.fold() }
    #endif
}
