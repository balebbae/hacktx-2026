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
    /// How long to wait for the other person's number, and how long the digits must stay unchanged before it counts
    /// (a full 10 digits, or a shorter number after a longer pause).
    var numberTimeout: TimeInterval = 60
    var numberSettle: TimeInterval = 1
    var numberPause: TimeInterval = 3
    /// Before coaching, wait until nobody has spoken for `pauseNeeded` seconds (give up waiting after `pauseMaxWait`).
    var pauseNeeded: TimeInterval = 2.5
    var pauseMaxWait: TimeInterval = 30
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
    /// Off on the phone: the loudness split cannot reliably tell the wearer from someone a metre away, and the
    /// router already requires an unknown person nearby.
    var requireBothSides = true
    /// From the first to the last segment in the window, so a few loud sentences are not "a conversation".
    var minDuration: TimeInterval = 0
    private var items: [(t: TimeInterval, words: Int, speaker: SpeakerGuess)] = []

    /// Adds a final segment; true (and starts over) once the window holds a conversation.
    mutating func add(_ seg: TranscriptSegment) -> Bool {
        items.append((seg.end, seg.text.split(separator: " ").count, seg.speaker))
        items.removeAll { $0.t < seg.end - seconds }
        guard items.reduce(0, { $0 + $1.words }) >= words,
              (items.last?.t ?? 0) - (items.first?.t ?? 0) >= minDuration,
              !requireBothSides || (items.contains(where: { $0.speaker == .user }) && items.contains(where: { $0.speaker == .other })) else { return false }
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
    static func lastSeen(name: String, bearing: Bearing) -> String { "I last saw \(name) at \(clock(bearing))." }
    static let noOneToRemember = nobody

    // Coaching the wearer through adding someone (spoken only in the glasses).
    static let coachAskConsent = "You're talking with someone new. Ask if they'd like to be added to your contacts, and to look at the camera."
    static let coachLookAtCamera = "Ask them to look at the camera."
    static let coachAskName = "Ask their name."
    static func coachAskNumber(name: String?) -> String { name.map { "Now ask \($0) for their number." } ?? "Now ask for their number." }
    static func coachHandPhone(name: String?) -> String { "Hand \(name ?? "them") your phone so they can type their number." }
    static func renamed(_ name: String) -> String { "Updated. That's \(name) now." }
    static let nobodyToUpdate = "I don't see anyone in your contacts to update."
    static let notInContactsYet = "They're not in your contacts yet."
    /// "Got 5 1 2, 5 5 5, 0 1 0 0." — digit by digit so the wearer can check it.
    static func gotNumber(_ digits: String) -> String {
        let d = Array(digits)
        let groups: [ArraySlice<Character>]
        if d.count == 10 { groups = [d[0..<3], d[3..<6], d[6..<10]] }
        else if d.count == 11, d.first == "1" { groups = [d[0..<1], d[1..<4], d[4..<7], d[7..<11]] }
        else { groups = [d[...]] }
        return "Got " + groups.map { $0.map(String.init).joined(separator: " ") }.joined(separator: ", ") + "."
    }
    static let noNumber = "No number. Saving without it."
}

/// Phone numbers from speech: numerals ("512-555-0100") and digit words ("five one two"), across pieces.
enum PhoneNumber {
    private static let words: [String: Character] = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]

    static func digits(in text: String) -> String {
        var out = ""
        var previousWasDigit = false
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if token.allSatisfy(\.isNumber) { out += token; previousWasDigit = true }
            else if let d = words[String(token)] { out.append(d); previousWasDigit = true }
            else if (token == "oh" || token == "o"), previousWasDigit { out += "0" }
            else { previousWasDigit = false }
        }
        return out
    }

    /// "(512) 555-0100", "+1 (512) 555-0100", otherwise the digits.
    static func format(_ d: String) -> String {
        let c = Array(d)
        if c.count == 10 { return "(\(String(c[0..<3]))) \(String(c[3..<6]))-\(String(c[6..<10]))" }
        if c.count == 11, c[0] == "1" { return "+1 (\(String(c[1..<4]))) \(String(c[4..<7]))-\(String(c[7..<11]))" }
        return d
    }
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
