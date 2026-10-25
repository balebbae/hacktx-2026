#if DEBUG
import Foundation
import MWDATCore
import MWDATMockDevice

/// Simulated Ray-Ban Meta for the Simulator and tests (DEBUG builds only). The mock
/// plays an HEVC file as the camera feed; `enroll_marcus_hevc.mov` is bundled for it.
enum GlassesMockDevice {
    static let defaultFixture = "enroll_marcus_hevc"

    static var isEnabled: Bool { GlassesSDK.isConfigured && MockDeviceKit.shared.isEnabled }
    static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Enables the Mock Device Kit (registered, permissions granted), pairs one pair of
    /// glasses, powers them on, unfolds and dons them, and points the camera at `fixture`.
    @discardableResult
    static func enable(fixtureNamed fixture: String = defaultFixture, bundle: Bundle = .main) throws -> any MockGlasses {
        guard GlassesSDK.configureIfNeeded() else { throw GlassesError.sdk(GlassesSDK.unavailableReason) }
        if !MockDeviceKit.shared.isEnabled {
            MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true))
        }
        let glasses: any MockGlasses
        if let existing = MockDeviceKit.shared.pairedDevices.first as? any MockGlasses {
            glasses = existing
        } else {
            glasses = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        }
        glasses.powerOn()
        glasses.unfold()
        glasses.don()
        if let url = bundle.url(forResource: fixture, withExtension: "mov") ?? bundle.url(forResource: fixture, withExtension: "mp4") {
            glasses.services.camera.setCameraFeed(fileURL: url)
        } else {
            glassesLog.error("mock fixture \(fixture) not in bundle")
        }
        return glasses
    }

    static var current: (any MockGlasses)? {
        guard isEnabled else { return nil }
        return MockDeviceKit.shared.pairedDevices.first as? any MockGlasses
    }

    static func fold() { current?.fold() }
    static func unfold() { current?.unfold() }

    static func disable() {
        if isEnabled { MockDeviceKit.shared.disable() }
    }
}
#endif
