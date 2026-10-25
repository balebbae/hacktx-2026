import Foundation
import AVFoundation
import os

// New types owned by S4. `Core/*` is frozen, so everything the flows need beyond the contracts lives here.

/// Timeouts and thresholds of the consent flow. Tests shrink them.
struct ConsentFlowConfig {
    var confirmTimeout: TimeInterval = 6
    var gatherTimeout: TimeInterval = 2
    var extraGatherTimeout: TimeInterval = 4
    var listenTimeout: TimeInterval = 6
    /// The wearer asks in their own words, so the other person's answer comes later than after our own question.
    var wearerAskTimeout: TimeInterval = 15
    var reaskTimeout: TimeInterval = 4
    var nameTimeout: TimeInterval = 6
    var minEmbeddings = 3
    var minQuality: Float = 0.3
    var clipLead: TimeInterval = 0.5
    var clipTail: TimeInterval = 0.7
    var pollInterval: TimeInterval = 0.1
    var nameConfidenceThreshold = 0.7
    var fallbackName = "Someone I met"
    static let `default` = ConsentFlowConfig()
}

/// Writes the few-second consent clip from whatever audio is in RAM. The real one wraps S3's `RingBuffer`;
/// `AudioChunkClipRecorder` below buffers `AudioChunk`s itself so the flow works before S3 lands.
protocol ConsentClipRecorder: AnyObject {
    /// Returns false when there is no audio for the window (the file is not created).
    func writeClip(from start: TimeInterval, to end: TimeInterval, url: URL) throws -> Bool
}

/// Keeps the last `seconds` of 16 kHz audio and writes 16-bit PCM WAV slices. Rolling: nothing older survives.
final class AudioChunkClipRecorder: ConsentClipRecorder, @unchecked Sendable {
    private struct Buffered { let start: TimeInterval; let samples: [Float]; let rate: Double }
    private let lock = OSAllocatedUnfairLock(initialState: [Buffered]())
    private var task: Task<Void, Never>?
    let seconds: TimeInterval

    init(seconds: TimeInterval = 30) { self.seconds = seconds }

    func start(audio: AudioInput) {
        stop()
        task = Task.detached { [weak self] in
            for await chunk in audio.subscribe() { self?.append(chunk) }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func append(_ chunk: AudioChunk) {
        lock.withLock { buf in
            buf.append(Buffered(start: chunk.timestamp, samples: chunk.samples, rate: chunk.sampleRate))
            let cutoff = chunk.timestamp - seconds
            buf.removeAll { $0.start + Double($0.samples.count) / $0.rate < cutoff }
        }
    }

    func slice(from start: TimeInterval, to end: TimeInterval) -> (samples: [Float], rate: Double) {
        let chunks = lock.withLock { $0 }
        var out: [Float] = []
        var rate = 16_000.0
        for c in chunks {
            rate = c.rate
            let cEnd = c.start + Double(c.samples.count) / c.rate
            guard cEnd > start, c.start < end else { continue }
            let lo = max(0, Int((start - c.start) * c.rate))
            let hi = min(c.samples.count, Int((end - c.start) * c.rate))
            if lo < hi { out.append(contentsOf: c.samples[lo..<hi]) }
        }
        return (out, rate)
    }

    func writeClip(from start: TimeInterval, to end: TimeInterval, url: URL) throws -> Bool {
        let (samples, rate) = slice(from: start, to: end)
        guard !samples.isEmpty else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WAVWriter.write(samples: samples, sampleRate: rate, to: url)
        return true
    }
}

/// Test recorder: always writes a short silent WAV so the file path can be asserted.
final class SilentClipRecorder: ConsentClipRecorder {
    private(set) var requests: [(TimeInterval, TimeInterval)] = []
    func writeClip(from start: TimeInterval, to end: TimeInterval, url: URL) throws -> Bool {
        requests.append((start, end))
        let n = Int(max(0.1, end - start) * 16_000)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WAVWriter.write(samples: [Float](repeating: 0, count: n), sampleRate: 16_000, to: url)
        return true
    }
}

enum WAVWriter {
    /// 16-bit little-endian mono PCM with a 44-byte header.
    static func data(samples: [Float], sampleRate: Double) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
    static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        try data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }
}

/// Where a known person was last seen (for "where is X" after they left the frame).
struct LastSeen: Equatable { let name: String; let personID: UUID; let bearing: Bearing; let at: TimeInterval }

/// "A conversation": at least `words` words within `seconds`, with both the wearer and someone else talking.
struct ConversationWindow {
    var seconds: TimeInterval = 45
    var words = 40
    private var items: [(t: TimeInterval, words: Int, speaker: SpeakerGuess)] = []

    /// Adds a final segment; true (and starts over) once the window holds a conversation.
    mutating func add(_ seg: TranscriptSegment) -> Bool {
        items.append((seg.end, seg.text.split(separator: " ").count, seg.speaker))
        items.removeAll { $0.t < seg.end - seconds }
        guard items.reduce(0, { $0 + $1.words }) >= words,
              items.contains(where: { $0.speaker == .user }), items.contains(where: { $0.speaker == .other }) else { return false }
        items.removeAll()
        return true
    }
}

/// A `CommandSource` you can push into (buttons, demo controls, tests).
final class ManualCommandSource: CommandSource, @unchecked Sendable {
    private let bus = EventBus<Command>()
    func subscribe() -> AsyncStream<Command> { bus.subscribe() }
    func send(_ c: Command) { bus.publish(c) }
}

extension Phrasebook {
    /// Not in Core's vocabulary; needed by `whereIs` once the person has left the frame.
    static func lastSeen(name: String, band: BearingBand) -> String {
        switch band {
        case .left, .farLeft: return "I last saw \(name) on your left."
        case .right, .farRight: return "I last saw \(name) on your right."
        case .ahead: return "I last saw \(name) ahead of you."
        }
    }
    static let noOneToRemember = nobody
}

/// Builds the flows. S5 calls these from `Services.make`.
enum FlowFactory {
    @MainActor
    static func makeConsentFlow(perception: Perception, transcriber: Transcriber, speaker: Speaker, cueGate: CueGate, peopleStore: PeopleStore, contacts: ContactsBridge, nameExtractor: NameExtractor, yesNo: YesNoClassifier, clipRecorder: ConsentClipRecorder, meeting: MeetingContextProvider, paths: MemoryPaths = .documents, userName: @escaping () -> String, nameGuess: NameGuessCache? = nil, config: ConsentFlowConfig = .default) -> SpokenConsentFlow {
        SpokenConsentFlow(perception: perception, transcriber: transcriber, speaker: speaker, cueGate: cueGate, peopleStore: peopleStore, contacts: contacts, nameExtractor: nameExtractor, yesNo: yesNo, clipRecorder: clipRecorder, meeting: meeting, paths: paths, userName: userName, nameGuess: nameGuess, config: config)
    }

    @MainActor
    static func makeCommandRouter(perception: Perception, speaker: Speaker, cueGate: CueGate, consentFlow: ConsentFlow, peopleStore: PeopleStore, contacts: ContactsBridge, setMode: @escaping (ChatterMode) -> Void, setMuted: @escaping (Bool) -> Void, rollCall: @escaping ([TrackSnapshot]) -> String = RollCall.phrase(tracks:)) -> CommandRouter {
        CommandRouter(perception: perception, speaker: speaker, cueGate: cueGate, consentFlow: consentFlow, peopleStore: peopleStore, contacts: contacts, setMode: setMode, setMuted: setMuted, rollCall: rollCall)
    }
}
