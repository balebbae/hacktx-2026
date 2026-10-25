import Foundation

/// Final segments containing a farewell → `.goodbyeDetected(t:)` (the consent flow's "they seem to have left" guard).
final class GoodbyeDetector: @unchecked Sendable {
    static let phrases = ["nice meeting you", "nice to meet you", "good meeting you", "good to meet you", "great meeting you", "see you", "take care", "catch you later", "talk to you later", "goodbye", "bye bye"]
    private let bus = EventBus<SpeechSignal>()
    private var task: Task<Void, Never>?
    var onGoodbye: ((TimeInterval) -> Void)?

    init() {}

    func subscribe() -> AsyncStream<SpeechSignal> { bus.subscribe() }

    static func isGoodbye(_ text: String) -> Bool {
        let s = CommandParser.normalize(text)
        return phrases.contains { s.contains($0) }
    }

    @discardableResult
    func feed(_ seg: TranscriptSegment) -> Bool {
        guard seg.isFinal, GoodbyeDetector.isGoodbye(seg.text) else { return false }
        bus.publish(.goodbyeDetected(t: seg.end))
        onGoodbye?(seg.end)
        return true
    }

    func attach(_ transcriber: Transcriber) {
        let stream = transcriber.subscribe()
        task = Task.detached { [weak self] in for await seg in stream { self?.feed(seg) } }
    }

    func detach() { task?.cancel(); task = nil }
}
