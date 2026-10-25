import Foundation
import os

/// Generic multi-subscriber fan-out. Every `subscribe()` in the app is backed by one of these:
/// one continuation per subscriber, removed when the consumer's stream terminates.
final class EventBus<T: Sendable>: @unchecked Sendable {
    private struct State { var continuations: [UUID: AsyncStream<T>.Continuation] = [:] }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let defaultPolicy: AsyncStream<T>.Continuation.BufferingPolicy

    init(defaultPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .unbounded) {
        self.defaultPolicy = defaultPolicy
    }

    func subscribe(bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy? = nil) -> AsyncStream<T> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: bufferingPolicy ?? defaultPolicy) { continuation in
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    func publish(_ value: T) {
        let targets = state.withLock { Array($0.continuations.values) }
        for c in targets { c.yield(value) }
    }

    func finishAll() {
        let targets = state.withLock { s -> [AsyncStream<T>.Continuation] in
            let v = Array(s.continuations.values); s.continuations.removeAll(); return v
        }
        for c in targets { c.finish() }
    }

    var subscriberCount: Int { state.withLock { $0.continuations.count } }
}
