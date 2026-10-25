import Foundation
import MWDATCore
import MWDATInputs
import os

/// Glasses gestures as `Command`s: double tap on the touchpad (`.select`) = who is here,
/// short capture-button press = remember them. A double press of the capture button
/// emits a short press first, so the short press is held for `debounce` and dropped if
/// a double press follows.
final class GlassesInputs: CommandSource, @unchecked Sendable {
    private let commands = EventBus<Command>()
    private let lock = OSAllocatedUnfairLock<(inputs: Inputs?, session: DeviceSession?, task: Task<Void, Never>?, pending: Task<Void, Never>?)>(initialState: (nil, nil, nil, nil))
    let debounce: Duration = .milliseconds(450)

    func subscribe() -> AsyncStream<Command> { commands.subscribe() }

    func attach(to session: DeviceSession) {
        detach()
        do {
            guard let inputs = try session.addInputs(configuration: InputsConfiguration(sources: [.captouch, .captureButton])) else {
                glassesLog.notice("inputs unavailable on this device")
                return
            }
            let task = Task { [weak self] in
                for await event in inputs.events {
                    self?.handle(event)
                }
            }
            lock.withLock { $0 = (inputs, session, task, nil) }
        } catch {
            glassesLog.error("addInputs failed: \(String(describing: error))")
        }
    }

    func detach() {
        let (session, task, pending) = lock.withLock { s -> (DeviceSession?, Task<Void, Never>?, Task<Void, Never>?) in
            let t = (s.session, s.task, s.pending)
            s = (nil, nil, nil, nil)
            return t
        }
        task?.cancel()
        pending?.cancel()
        if let session { try? session.removeInputs() }
    }

    func handle(_ event: InputEvent) {
        switch event {
        case .select:
            commands.publish(.whoIsHere)
        case .capture(let kind, _, _):
            switch kind {
            case .shortPress:
                let pending = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { return }
                    self.lock.withLock { $0.pending = nil }
                    self.commands.publish(.rememberThem)
                }
                let previous = lock.withLock { s -> Task<Void, Never>? in
                    let p = s.pending
                    s.pending = pending
                    return p
                }
                previous?.cancel()
            case .doublePress:
                let pending = lock.withLock { s -> Task<Void, Never>? in
                    let p = s.pending
                    s.pending = nil
                    return p
                }
                pending?.cancel()
                commands.publish(.cancel)
            default:
                break
            }
        default:
            break
        }
    }
}
