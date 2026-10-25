import Foundation
import CoreHaptics
import SwiftUI

/// The haptic vocabulary (docs/DESIGN_SPEC.md §8): each kind is one short Core Haptics pattern, never a loop.
enum HapticKind: CaseIterable {
    /// Listening starts: one light tap.
    case listen
    /// Command accepted: one soft micro-bob.
    case accepted
    /// A known person entered: double-light.
    case cue
    /// A known person left: a single, softer tap.
    case left
    /// Consent accepted: a rising, success-like pattern.
    case consent
    /// Awareness paused: one low, soft tap.
    case paused
    /// Error or lost connection: one soft warning, not repeated.
    case error

    /// Plain-text description, for the settings preview.
    var title: String {
        switch self {
        case .listen: return "Listening"
        case .accepted: return "Accepted"
        case .cue: return "Someone you know"
        case .left: return "Someone left"
        case .consent: return "They said yes"
        case .paused: return "Paused"
        case .error: return "Something went wrong"
        }
    }
}

/// Plays Familiar's haptics through a lazily created `CHHapticEngine`. Silent (no-op) when the device has no haptic
/// hardware, when the engine cannot start, or when the user turned haptics off (UserDefaults "hapticsEnabled",
/// default on). Safe to call from the main thread at any time; never throws, never blocks.
enum FamiliarHaptics {
    /// UserDefaults key read before every pattern. The Accessibility settings toggle writes it.
    static let enabledKey = "hapticsEnabled"

    /// `true` unless the user turned haptics off.
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil { return true }
        return defaults.bool(forKey: enabledKey)
    }

    /// `true` when this device can play Core Haptics patterns.
    static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Plays one pattern. Does nothing when haptics are unsupported or disabled.
    static func play(_ kind: HapticKind) {
        guard isEnabled else { return }
        HapticEngineBox.shared.play(events: events(for: kind))
    }

    /// Starts the engine ahead of the first cue so the first tap is not late. Optional.
    static func prepare() {
        guard isEnabled else { return }
        HapticEngineBox.shared.prepare()
    }

    // MARK: Patterns

    static func events(for kind: HapticKind) -> [CHHapticEvent] {
        switch kind {
        case .listen:
            return [transient(intensity: 0.45, sharpness: 0.35, at: 0)]
        case .accepted:
            return [transient(intensity: 0.55, sharpness: 0.5, at: 0)]
        case .cue:
            return [transient(intensity: 0.5, sharpness: 0.4, at: 0),
                    transient(intensity: 0.62, sharpness: 0.4, at: 0.11)]
        case .left:
            return [transient(intensity: 0.35, sharpness: 0.2, at: 0)]
        case .consent:
            return [transient(intensity: 0.5, sharpness: 0.45, at: 0),
                    continuous(intensity: 0.35, sharpness: 0.3, at: 0.08, duration: 0.22),
                    transient(intensity: 0.9, sharpness: 0.65, at: 0.34)]
        case .paused:
            return [transient(intensity: 0.4, sharpness: 0.12, at: 0)]
        case .error:
            return [continuous(intensity: 0.55, sharpness: 0.22, at: 0, duration: 0.18),
                    transient(intensity: 0.35, sharpness: 0.2, at: 0.24)]
        }
    }

    private static func transient(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time)
    }

    private static func continuous(intensity: Float, sharpness: Float, at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time,
                      duration: duration)
    }
}

/// Owns the one `CHHapticEngine`. Created on first use; restarted after the system stops or resets it.
private final class HapticEngineBox: @unchecked Sendable {
    static let shared = HapticEngineBox()

    private var engine: CHHapticEngine?
    private var unavailable: Bool = false
    private var needsStart: Bool = true
    private let lock = NSRecursiveLock()

    func prepare() {
        _ = startedEngine()
    }

    func play(events: [CHHapticEvent]) {
        guard let engine = startedEngine() else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // One failed pattern is not worth a retry loop; the next cue tries again.
        }
    }

    private func startedEngine() -> CHHapticEngine? {
        lock.lock()
        defer { lock.unlock() }
        if unavailable { return nil }
        if engine == nil {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
                unavailable = true
                return nil
            }
            do {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.isAutoShutdownEnabled = true
                created.stoppedHandler = { [weak self] _ in self?.markNeedsStart() }
                created.resetHandler = { [weak self] in self?.markNeedsStart() }
                engine = created
            } catch {
                unavailable = true
                return nil
            }
        }
        if needsStart, let engine {
            do {
                try engine.start()
                needsStart = false
            } catch {
                return nil
            }
        }
        return engine
    }

    private func markNeedsStart() {
        lock.lock()
        needsStart = true
        lock.unlock()
    }
}

extension View {
    /// Plays a Familiar haptic whenever `trigger` changes (respects the "hapticsEnabled" setting).
    func familiarHaptic<T: Equatable>(_ kind: HapticKind, trigger: T) -> some View {
        onChange(of: trigger) { _, _ in FamiliarHaptics.play(kind) }
    }
}

// MARK: - Preview

#Preview("Haptics") {
    struct Host: View {
        @Environment(\.visionScale) private var scale
        @AppStorage(FamiliarHaptics.enabledKey) private var hapticsEnabled: Bool = true
        var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .font(FamiliarType.body(scale))
                        .tint(FamiliarPalette.ocean)
                        .surfaceCard(padding: 16)
                    ForEach(HapticKind.allCases, id: \.self) { kind in
                        Button(kind.title) { FamiliarHaptics.play(kind) }
                            .buttonStyle(GhostPillStyle())
                            .accessibilityHint("Plays this pattern")
                    }
                    Text(FamiliarHaptics.isSupported ? "This device plays haptics." : "This device has no haptic hardware; every pattern is silent.")
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                        .multilineTextAlignment(.center)
                }
                .padding(FamiliarPalette.margin)
            }
            .familiarCanvas()
        }
    }
    return Host()
}
