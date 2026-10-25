import Foundation
import QuartzCore
import os

/// Reads a transcript (`other: …` / `user: …` lines) and emits one final `TranscriptSegment` every `interval` seconds.
/// Keeps a rolling 90 s window like the real transcriber.
final class FakeTranscriber: Transcriber, @unchecked Sendable {
    typealias Clock = () -> TimeInterval

    struct Line: Equatable { let speaker: SpeakerGuess; let text: String }

    let lines: [Line]
    let interval: TimeInterval
    var windowSeconds: TimeInterval = 90
    var loops = false
    private let clock: Clock
    private let bus = EventBus<TranscriptSegment>()
    private let state = OSAllocatedUnfairLock(initialState: [TranscriptSegment]())
    private var task: Task<Void, Never>?

    init(lines: [Line], interval: TimeInterval = 2.5, clock: @escaping Clock = { CACurrentMediaTime() }) {
        self.lines = lines
        self.interval = interval
        self.clock = clock
    }

    convenience init(text: String, interval: TimeInterval = 2.5, clock: @escaping Clock = { CACurrentMediaTime() }) {
        self.init(lines: FakeTranscriber.parse(text), interval: interval, clock: clock)
    }

    convenience init?(transcriptNamed name: String, bundle: Bundle = .main, interval: TimeInterval = 2.5) {
        let base = (name as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: base, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(text: text, interval: interval)
    }

    static func parse(_ text: String) -> [Line] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let lower = line.lowercased()
            if lower.hasPrefix("other:") { return Line(speaker: .other, text: String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)) }
            if lower.hasPrefix("user:") { return Line(speaker: .user, text: String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
            return Line(speaker: .none, text: line)
        }
    }

    func subscribe() -> AsyncStream<TranscriptSegment> { bus.subscribe() }

    func start(audio: AudioInput) async throws {
        guard task == nil else { return }
        task = Task.detached { [weak self] in
            guard let self else { return }
            repeat {
                for line in self.lines {
                    try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                    if Task.isCancelled { return }
                    self.emit(line)
                }
            } while self.loops && !Task.isCancelled
        }
    }

    /// Emit a line immediately (tests and demo controls).
    func emit(_ line: Line) {
        let end = clock()
        let seg = TranscriptSegment(text: line.text, start: end - min(interval, 0.3 * Double(line.text.split(separator: " ").count)), end: end, isFinal: true, speaker: line.speaker)
        append(seg)
        bus.publish(seg)
    }

    /// Inject an already-built segment (tests).
    func append(_ seg: TranscriptSegment) {
        state.withLock { segs in
            segs.append(seg)
            let cutoff = seg.end - windowSeconds
            segs.removeAll { $0.end < cutoff }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] {
        let cutoff = clock() - min(seconds, windowSeconds)
        return state.withLock { $0.filter { $0.end >= cutoff } }
    }
}
