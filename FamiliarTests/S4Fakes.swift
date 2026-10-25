import Foundation
import QuartzCore
@testable import Familiar

/// Controllable perception for flow/router tests (ScriptedPerception is time-driven; this one is not).
final class FakePerception: Perception, @unchecked Sendable {
    private let bus = EventBus<PerceptionEvent>()
    var tracks: [TrackSnapshot] = []
    var embeddingsPerTrack = 3
    var embeddingQuality: Float = 0.9
    private(set) var bursts: [(track: Int, seconds: Double)] = []
    private(set) var assigned: [(track: Int, personID: UUID, name: String)] = []

    func subscribe() -> AsyncStream<PerceptionEvent> { bus.subscribe() }
    func publish(_ e: PerceptionEvent) { bus.publish(e) }
    func start(frames: FrameSource, gallery: GalleryProvider) async throws {}
    func stop() {}
    func currentTracks() -> [TrackSnapshot] { tracks }
    func bestEmbeddings(track: Int, max: Int) -> [FaceEmbedding] {
        guard tracks.contains(where: { $0.trackID == track }) else { return [] }
        return (0..<Swift.min(max, embeddingsPerTrack)).map { i in
            FaceEmbedding(modelID: "fake", vector: Array(repeating: Float(i + 1) / 10, count: 512), quality: embeddingQuality - Float(i) * 0.05, timestamp: CACurrentMediaTime(), thumbnailJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        }
    }
    func requestBurst(track: Int, seconds: Double) { bursts.append((track, seconds)) }
    func assignIdentity(track: Int, personID: UUID, name: String) {
        assigned.append((track, personID, name))
        tracks = tracks.map { t in
            t.trackID == track ? TrackSnapshot(trackID: t.trackID, identity: .known(personID: personID, name: name, score: 1), bearing: t.bearing, distance: t.distance, faceBox: t.faceBox, faceHeightPx: t.faceHeightPx, yawDegrees: t.yawDegrees, isFacingUser: t.isFacingUser, mouthOpenness: t.mouthOpenness, quality: t.quality, timestamp: t.timestamp) : t
        }
    }

    static func track(_ id: Int, identity: Identity = .unknown(bestScore: nil), band: BearingBand = .ahead, distance: Distance = .close, faceHeightPx: Int = 300, facing: Bool = true) -> TrackSnapshot {
        TrackSnapshot(trackID: id, identity: identity, bearing: Bearing(degrees: band.centerDegrees(hFOV: 70), band: band), distance: distance, faceBox: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), faceHeightPx: faceHeightPx, yawDegrees: 0, isFacingUser: facing, mouthOpenness: 0.1, quality: 0.9, timestamp: CACurrentMediaTime())
    }
}

final class FakeConsentFlow: ConsentFlow, @unchecked Sendable {
    private let bus = EventBus<ConsentState>()
    private(set) var begins: [Bool] = []
    private(set) var cancels = 0
    func subscribe() -> AsyncStream<ConsentState> { bus.subscribe() }
    func begin(confirmFirst: Bool) async { begins.append(confirmFirst) }
    func tapAnswer(yes: Bool) {}
    func cancel() { cancels += 1 }
    func publish(_ s: ConsentState) { bus.publish(s) }
}

struct FixedName: NameExtractor {
    let guess: NameGuess
    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess { guess }
}

func seg(_ speaker: SpeakerGuess, _ text: String, at t: TimeInterval = CACurrentMediaTime()) -> TranscriptSegment {
    TranscriptSegment(text: text, start: t - 1, end: t, isFinal: true, speaker: speaker)
}

func makePerson(name: String = "Marcus", id: UUID = UUID(), modelID: String = "fake") -> Person {
    Person(id: id, name: name, phone: nil,
           embeddings: [FaceEmbedding(modelID: modelID, vector: Array(repeating: 0.1, count: 512), quality: 0.9, timestamp: 0, thumbnailJPEG: nil)],
           thumbnailPath: "thumbs/\(id.uuidString).jpg",
           consent: ConsentRecord(kind: .tap, at: Date(), askedText: "q", replyTranscript: "", clipURL: nil),
           met: MeetingContext(at: Date(), placeName: "HackTX", latitude: nil, longitude: nil), contactIdentifier: nil)
}
