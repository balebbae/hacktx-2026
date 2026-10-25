import CoreMedia
import Foundation
import MWDATCamera
import MWDATCore
import QuartzCore
import os

/// One-time Meta Wearables DAT setup and the registration callback URL hop.
enum GlassesSDK {
    private struct State { var attempted = false; var configured = false; var failure: String? }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// True once `Wearables.configure()` succeeded. `Wearables.shared` traps when it did not,
    /// so every caller checks this first. It fails in unsigned builds (`CODE_SIGNING_ALLOWED=NO`).
    static var isConfigured: Bool { state.withLock { $0.configured } }
    static var configurationFailure: String? { state.withLock { $0.failure } }

    /// Safe to call many times; `Wearables.configure()` must run before `Wearables.shared`.
    @discardableResult
    static func configureIfNeeded() -> Bool {
        let first = state.withLock { s -> Bool in
            if s.attempted { return false }
            s.attempted = true
            return true
        }
        guard first else { return isConfigured }
        do {
            try Wearables.configure()
            state.withLock { $0.configured = true }
        } catch {
            let reason = error.errorDescription ?? String(describing: error)
            glassesLog.error("Wearables.configure failed: \(reason)")
            state.withLock { $0.failure = reason }
        }
        return isConfigured
    }

    static var unavailableReason: String {
        "Glasses SDK unavailable: \(configurationFailure ?? "not configured"). Build with code signing on."
    }

    /// The Meta AI app calls back on `familiar://...?metaWearablesAction=...` after the user approves.
    static func isCallbackURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains { $0.name == "metaWearablesAction" } == true
    }

    @discardableResult
    static func handle(url: URL) async -> Bool {
        guard isCallbackURL(url), configureIfNeeded() else { return false }
        do { return try await Wearables.shared.handleUrl(url) } catch {
            glassesLog.error("handleUrl failed: \(String(describing: error))")
            return false
        }
    }
}

let glassesLog = Logger(subsystem: "familiar", category: "glasses")

/// Entry point S5 calls from `Services.make` for `Source.glasses`.
enum GlassesFactory {
    static func makeFrameSource() -> FrameSource { GlassesFrameSource() }
    static func makeFrameSource(options: GlassesFrameSource.Options) -> GlassesFrameSource { GlassesFrameSource(options: options) }
}

/// Live frames from Ray-Ban Meta glasses over Bluetooth Classic via the Meta DAT.
/// HEVC 24 fps medium resolution, decoded in software to 32BGRA. Frames are published
/// with host-clock timestamps (first PTS mapped to `CACurrentMediaTime()`).
final class GlassesFrameSource: FrameSource, GlassesStreamCoordinator, @unchecked Sendable {
    struct Options: Sendable {
        /// Also pull the glasses microphone through the stream (dev only: not beamformed,
        /// ~200 ms behind video). Exposed as `audioInput`.
        var streamAudio = false
        /// Map glasses gestures to `Command`s. Exposed as `commandSource`.
        var inputs = false
        var frameRate: UInt = 24
    }

    private struct State {
        var status: GlassesStatus = .idle
        var isStreaming = false
        var session: DeviceSession?
        var camera: Camera?
        var ptsBase: Double?
        var hostBase: Double = 0
        var lastTimestamp: TimeInterval = 0
        var windowStart: Double = 0
        var windowCount = 0
        var fps: Double = 0
        var totalFrames = 0
        var droppedFrames = 0
        var lowQualityLogged = false
    }

    let options: Options
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let frames = EventBus<Frame>(defaultPolicy: .bufferingNewest(1))
    private let statuses = EventBus<GlassesStatus>()
    private let streaming = EventBus<Bool>()
    private let decoder = HEVCFrameDecoder()
    private let tokens = ListenerTokenBag()
    static let connectTimeout: TimeInterval = 8
    private var deviceToken: (any AnyListenerToken)?

    /// Non-nil when `options.streamAudio`; valid for the life of the source.
    let audioInput: GlassesStreamAudioInput?
    /// Non-nil when `options.inputs`.
    let commandSource: GlassesInputs?

    init(options: Options = Options()) {
        self.options = options
        audioInput = options.streamAudio ? GlassesStreamAudioInput() : nil
        commandSource = options.inputs ? GlassesInputs() : nil
    }

    deinit { stop() }

    // MARK: FrameSource

    func subscribe() -> AsyncStream<Frame> { frames.subscribe() }

    func start() async throws {
        guard GlassesSDK.configureIfNeeded() else {
            set(.failed(reason: GlassesSDK.unavailableReason))
            throw GlassesError.sdk(GlassesSDK.unavailableReason)
        }
        let wearables = Wearables.shared
        guard wearables.registrationState == .registered else {
            set(.notRegistered)
            throw GlassesError.notRegistered
        }
        stop()
        set(.connecting)
        let selector = AutoDeviceSelector(wearables: wearables)
        let deadline = CACurrentMediaTime() + Self.connectTimeout
        guard await Self.waitForLinkedDevice(wearables, selector: selector, deadline: deadline) else {
            set(.failed(reason: GlassesError.noDevice.errorDescription ?? "No glasses"))
            throw GlassesError.noDevice
        }

        var permission = try await wearables.checkPermissionStatus(.camera)
        if permission != .granted {
            permission = try await wearables.requestPermission(.camera)
        }
        guard permission == .granted else {
            set(.cameraPermissionDenied)
            throw GlassesError.cameraPermissionDenied
        }

        var lastError = GlassesError.noDevice.errorDescription ?? "No glasses"
        while CACurrentMediaTime() < deadline {
            guard await Self.waitForLinkedDevice(wearables, selector: selector, deadline: deadline) else { break }
            do {
                try openSession(wearables, selector: selector)
                return
            } catch {
                lastError = error.localizedDescription
                glassesLog.info("session open retry: \(lastError)")
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        set(.failed(reason: lastError))
        throw GlassesError.sdk(lastError)
    }

    /// Glasses become eligible a moment after they are powered on, unfolded and linked
    /// (the mock too). Permission checks and `createSession` both fail before that.
    private static func waitForLinkedDevice(_ wearables: any WearablesInterface, selector: AutoDeviceSelector, deadline: Double) async -> Bool {
        while true {
            if let id = selector.activeDevice, wearables.deviceForIdentifier(id)?.linkState == .connected { return true }
            if CACurrentMediaTime() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// `start()` retries this until `connectTimeout`.
    private func openSession(_ wearables: any WearablesInterface, selector: AutoDeviceSelector) throws {
        let session: DeviceSession
        do {
            session = try wearables.createSession(deviceSelector: selector)
        } catch {
            throw GlassesError.sdk(Self.describe(error))
        }
        state.withLock { $0.session = session }

        session.statePublisher.listen { [weak self] sessionState in
            self?.handleSession(state: sessionState, session: session)
        }.store(in: tokens)
        session.errorPublisher.listen { [weak self] error in
            glassesLog.error("session error: \(String(describing: error))")
            self?.fail(reason: Self.describe(error))
        }.store(in: tokens)

        do { try session.start() } catch {
            let reason = Self.describe(error)
            state.withLock { $0.session = nil }
            tokens.clear()
            session.stop()
            throw GlassesError.sdk(reason)
        }
    }

    func stop() { stop(final: nil) }

    // MARK: GlassesStreamCoordinator

    var isStreaming: Bool { state.withLock { $0.isStreaming } }
    var status: GlassesStatus { state.withLock { $0.status } }
    var framesPerSecond: Double { state.withLock { $0.fps } }
    var frameCounts: (total: Int, dropped: Int) { state.withLock { ($0.totalFrames, $0.droppedFrames) } }
    func streamingChanges() -> AsyncStream<Bool> { streaming.subscribe() }
    func statusChanges() -> AsyncStream<GlassesStatus> { statuses.subscribe() }

    // MARK: Session lifecycle

    private func handleSession(state sessionState: DeviceSessionState, session: DeviceSession) {
        glassesLog.info("session \(String(describing: sessionState))")
        switch sessionState {
        case .started:
            addCamera(to: session)
            watchDevice(of: session)
        case .stopped:
            if status.isActive { stop(final: .stopped(reason: "Glasses disconnected")) }
        default:
            break
        }
    }

    private func addCamera(to session: DeviceSession) {
        let alreadyAdded = state.withLock { $0.camera != nil }
        guard !alreadyAdded else { return }
        let config: StreamConfiguration
        if options.streamAudio {
            config = StreamConfiguration(videoCodec: .hvc1,
                                         audioCodec: .pcm(sampleRate: .rate16000, numberOfChannels: 1),
                                         resolution: .medium,
                                         frameRate: options.frameRate)
        } else {
            config = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: options.frameRate)
        }
        let camera: Camera
        do {
            guard let added = try session.addCamera(config: config) else {
                fail(reason: "The glasses did not offer a camera")
                return
            }
            camera = added
        } catch {
            fail(reason: Self.describe(error))
            return
        }
        state.withLock { $0.camera = camera }

        let stream = camera.stream
        stream.statePublisher.listen { [weak self] streamState in
            self?.handleStream(state: streamState)
        }.store(in: tokens)
        stream.errorPublisher.listen { [weak self] error in
            self?.handleStream(error: error)
        }.store(in: tokens)
        stream.videoFramePublisher.listen { [weak self] videoFrame in
            self?.handle(videoFrame: videoFrame)
        }.store(in: tokens)
        if let audioInput {
            stream.audioFramePublisher.listen { audioFrame in
                audioInput.handle(audioFrame: audioFrame)
            }.store(in: tokens)
        }
        if let commandSource {
            commandSource.attach(to: session)
        }
        stream.start()
    }

    private func watchDevice(of session: DeviceSession) {
        guard GlassesSDK.isConfigured, let device = Wearables.shared.deviceForIdentifier(session.deviceId) else { return }
        deviceToken = device.addDeviceStateListener { [weak self] deviceState in
            self?.handle(deviceState: deviceState)
        }
    }

    private func handle(deviceState: DeviceState) {
        guard status.isActive else { return }
        if deviceState.hingeState == .closed {
            stop(final: .stopped(reason: "Glasses folded"))
        } else if deviceState.donState == .doffed {
            glassesLog.notice("glasses taken off")
        }
        switch deviceState.thermalLevel {
        case .critical, .emergency, .shutdown:
            stop(final: .stopped(reason: "Glasses too hot"))
        default:
            break
        }
        if let battery = deviceState.batteryLevel, battery <= 5 {
            glassesLog.notice("glasses battery \(battery)%")
        }
    }

    private func handleStream(state streamState: StreamState) {
        glassesLog.info("stream \(String(describing: streamState))")
        switch streamState {
        case .waitingForDevice, .starting:
            set(.connecting)
        case .streaming:
            // DAT reports streaming up to ~12 s before the first frame arrives.
            if !isStreaming { set(.waitingForFrames) }
        case .paused:
            setStreaming(false)
            set(.paused)
        case .stopped:
            if status.isActive { stop(final: .stopped(reason: "Stream stopped")) }
        default:
            break
        }
    }

    private func handleStream(error: StreamError) {
        glassesLog.error("stream error: \(String(describing: error))")
        switch error {
        case .hingesClosed: stop(final: .stopped(reason: "Glasses folded"))
        case .thermalHot: stop(final: .stopped(reason: "Glasses too hot"))
        case .batteryLow: stop(final: .stopped(reason: "Glasses battery low"))
        case .peakPowerLimit: stop(final: .stopped(reason: "Glasses power limit"))
        case .permissionDenied: stop(final: .cameraPermissionDenied)
        case .deviceNotConnected, .deviceNotFound: stop(final: .stopped(reason: "Glasses disconnected"))
        case .timeout: stop(final: .failed(reason: "Glasses stream timed out"))
        default: fail(reason: Self.describe(error))
        }
    }

    // MARK: Frames

    private func handle(videoFrame: VideoFrame) {
        guard let pixelBuffer = decoder.decode(videoFrame.sampleBuffer) else {
            state.withLock { $0.droppedFrames += 1 }
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(videoFrame.sampleBuffer)
        let now = CACurrentMediaTime()
        let (timestamp, becameStreaming) = state.withLock { s -> (TimeInterval, Bool) in
            var t = now
            if pts.isValid && pts.isNumeric {
                let p = CMTimeGetSeconds(pts)
                if let base = s.ptsBase, p >= base - 1 {
                    t = s.hostBase + (p - base)
                } else {
                    s.ptsBase = p
                    s.hostBase = now
                }
                if t > now { t = now }
            }
            if t <= s.lastTimestamp { t = s.lastTimestamp + 0.001 }
            s.lastTimestamp = t
            s.totalFrames += 1
            s.windowCount += 1
            if s.windowStart == 0 { s.windowStart = now }
            if now - s.windowStart >= 1 {
                s.fps = Double(s.windowCount) / (now - s.windowStart)
                s.windowStart = now
                s.windowCount = 0
            }
            let became = !s.isStreaming
            s.isStreaming = true
            if became { s.status = .streaming }
            return (t, became)
        }
        if becameStreaming {
            glassesLog.notice("first glasses frame")
            streaming.publish(true)
            statuses.publish(.streaming)
        }
        frames.publish(Frame(pixelBuffer: pixelBuffer,
                             timestamp: timestamp,
                             orientation: GlassesCameraGeometry.orientation,
                             horizontalFOVDegrees: GlassesCameraGeometry.horizontalFOVDegrees,
                             verticalFOVDegrees: GlassesCameraGeometry.verticalFOVDegrees))
    }

    // MARK: State helpers

    private func set(_ newStatus: GlassesStatus) {
        let changed = state.withLock { s -> Bool in
            guard s.status != newStatus else { return false }
            s.status = newStatus
            return true
        }
        if changed { statuses.publish(newStatus) }
    }

    private func setStreaming(_ value: Bool) {
        let changed = state.withLock { s -> Bool in
            guard s.isStreaming != value else { return false }
            s.isStreaming = value
            if !value { s.fps = 0 }
            return true
        }
        if changed { streaming.publish(value) }
    }

    private func fail(reason: String) { stop(final: .failed(reason: reason)) }

    /// Tears the stream and session down. `final` is the status to publish; nil means a
    /// plain user stop. Dispatched off the caller because the SDK may invoke us from
    /// inside one of its own callbacks.
    private func stop(final: GlassesStatus?) {
        let (session, camera) = state.withLock { s -> (DeviceSession?, Camera?) in
            let pair = (s.session, s.camera)
            s.session = nil
            s.camera = nil
            s.ptsBase = nil
            s.windowStart = 0
            s.windowCount = 0
            return pair
        }
        commandSource?.detach()
        tokens.clear()
        deviceToken = nil
        decoder.reset()
        setStreaming(false)
        if session != nil || camera != nil || status.isActive {
            set(final ?? .stopped(reason: "Stopped"))
        } else if let final {
            set(final)
        }
        guard session != nil || camera != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            camera?.stream.stop()
            session?.stop()
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        return String(describing: error)
    }
}
