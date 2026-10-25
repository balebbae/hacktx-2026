// Familiar/Core/Contracts.swift
// These contracts are copied verbatim from AGENTS.md. Do not change signatures.
// Only sessions S1, S5 and S6 may edit this file.

import Foundation
import CoreVideo
import CoreGraphics
import ImageIO

struct Frame { let pixelBuffer: CVPixelBuffer; let timestamp: TimeInterval; let orientation: CGImagePropertyOrientation; let horizontalFOVDegrees: Double; let verticalFOVDegrees: Double }
protocol FrameSource: AnyObject { func subscribe() -> AsyncStream<Frame>; func start() async throws; func stop() }   // the app starts/stops sources

struct AudioChunk { let samples: [Float]; let sampleRate: Double /* 16_000 */; let timestamp: TimeInterval }
enum AudioRoute { case phoneMicGlassesA2DP, glassesHFP, glassesStreamMic, phoneOnly }
protocol AudioInput: AnyObject { func subscribe() -> AsyncStream<AudioChunk>; var route: AudioRoute { get }; var micLevel: Float { get } }

enum Distance { case close, medium, far }                                    // calibrated: < 1.5 m, 1.5–3 m, > 3 m
enum BearingBand { case farLeft, left, ahead, right, farRight }
struct Bearing { let degrees: Double /* + = right, from true FOV */; let band: BearingBand }
enum Identity { case known(personID: UUID, name: String, score: Float); case unknown(bestScore: Float?) }
struct TrackSnapshot { let trackID: Int; let identity: Identity; let bearing: Bearing; let distance: Distance; let faceBox: CGRect /* normalized, top-left origin */; let faceHeightPx: Int; let yawDegrees: Double?; let isFacingUser: Bool; let mouthOpenness: Double?; let quality: Float; let timestamp: TimeInterval }
enum CueKind { case wave, smile }
enum PerceptionEvent { case snapshot(tracks: [TrackSnapshot], preview: CGImage?); case knownAppeared(TrackSnapshot); case knownApproaching(TrackSnapshot); case knownArrived(TrackSnapshot); case knownLeft(personID: UUID, name: String, last: Bearing); case unknownCountChanged(Int); case speakingStarted(TrackSnapshot); case cue(personID: UUID, name: String, kind: CueKind) }
struct FaceEmbedding { let modelID: String /* "w600k_mbf" */; let vector: [Float]; let quality: Float; let timestamp: TimeInterval; let thumbnailJPEG: Data? /* 256×256, 20 % margin, from full-res */ }
protocol EmbeddingProvider { var modelID: String { get }; var dimension: Int { get }; func embed(_ alignedFace112: CVPixelBuffer) async throws -> [Float] }
struct Gallery { let modelID: String; let people: [(personID: UUID, name: String, embeddings: [[Float]])] }
protocol GalleryProvider: AnyObject { func gallery() -> Gallery }   // lock-protected snapshot, re-read at every match
protocol Perception: AnyObject {
  func subscribe() -> AsyncStream<PerceptionEvent>
  func start(frames: FrameSource, gallery: GalleryProvider) async throws; func stop()
  func currentTracks() -> [TrackSnapshot]
  func bestEmbeddings(track: Int, max: Int) -> [FaceEmbedding]      // quality desc
  func requestBurst(track: Int, seconds: Double)                    // 4 embeds/s
  func assignIdentity(track: Int, personID: UUID, name: String)      // label flips at `saving`
}

enum SpeakerGuess { case user, other, none }
struct TranscriptSegment { let text: String; let start: TimeInterval; let end: TimeInterval; let isFinal: Bool; let speaker: SpeakerGuess }
protocol Transcriber: AnyObject { func subscribe() -> AsyncStream<TranscriptSegment>; func start(audio: AudioInput) async throws; func stop(); func recentSegments(seconds: TimeInterval) -> [TranscriptSegment] }
protocol VoiceActivity: AnyObject { func subscribe() -> AsyncStream<(isSpeech: Bool, guess: SpeakerGuess, t: TimeInterval)>; func calibrateUser(seconds: Double) async }
enum ChatterMode { case quiet, normal, chatty }
enum Command { case whoIsHere, rememberThem, setMode(ChatterMode), mute, unmute, call(String), text(String), whereIs(String), cancel, repeatLast, describeSurroundings }
protocol CommandSource: AnyObject { func subscribe() -> AsyncStream<Command> }

enum Audience { case user, otherPerson }
struct Utterance { let text: String; let priority: Int /* 0 interrupt … 3 low */; let category: String; let personID: UUID?; let dedupeKey: String?; let audience: Audience; let earcon: Bool }
protocol Speaker: AnyObject { @discardableResult func speak(_ u: Utterance) async -> ClosedRange<TimeInterval>?; func stopAll(); var isSpeaking: Bool { get }; func prewarm(_ phrases: [String]) async }
protocol CuePolicy { func utterances(for e: PerceptionEvent, mode: ChatterMode, now: TimeInterval) -> [Utterance] }   // pure, unit-tested
final class CueGate { var muted: Bool; var consentActive: Bool; var userSpeaking: Bool; func admit(_ u: Utterance) -> Bool /* priority 0 always */ { u.priority == 0 || !(muted || consentActive || userSpeaking) }
  init(muted: Bool = false, consentActive: Bool = false, userSpeaking: Bool = false) { self.muted = muted; self.consentActive = consentActive; self.userSpeaking = userSpeaking } }

struct ConsentRecord { enum Kind { case spoken, tap }; let kind: Kind; let at: Date; let askedText: String; let replyTranscript: String; let clipURL: URL? }
struct MeetingContext { let at: Date; let placeName: String?; let latitude: Double?; let longitude: Double? }
struct Person: Identifiable, Codable { let id: UUID; var name: String; var phone: String?; var embeddings: [FaceEmbedding]; var thumbnailPath: String; var consent: ConsentRecord; var met: MeetingContext; var contactIdentifier: String? }
protocol PeopleStore: GalleryProvider { func all() -> [Person]; func add(_ p: Person) throws; func remove(id: UUID) throws /* row + files + CNContact */; func find(name: String) -> Person?; func changes() -> AsyncStream<Void> }   // @MainActor JSON store
protocol ContactsBridge { func create(for p: Person) async throws -> String; func delete(identifier: String) async throws; func call(_ p: Person); func text(_ p: Person) }

struct NameGuess { let name: String?; let confidence: Double; let source: String /* regex | fm | meta */ }
protocol NameExtractor { func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess }
enum YesNo { case yes, no, unclear }
protocol YesNoClassifier { func classify(_ reply: String) async -> YesNo }
enum ConsentState { case idle, confirmingWithUser, gathering(track: Int), asking(name: String?), listening, saving, done(Person), declined, cancelled(reason: String) }
protocol ConsentFlow: AnyObject { func subscribe() -> AsyncStream<ConsentState>; func begin(confirmFirst: Bool) async; func tapAnswer(yes: Bool); func cancel() }

// MARK: - Synthesized conformances (must live in the declaring file; the block above stays verbatim)
extension FaceEmbedding: Codable, Equatable {}
extension ConsentRecord.Kind: Codable, Equatable {}
extension ConsentRecord: Codable, Equatable {}
extension MeetingContext: Codable, Equatable {}
extension Person: Equatable {}

extension Distance: Codable, Equatable, CaseIterable {}
extension BearingBand: Codable, Equatable, CaseIterable {}
extension ChatterMode: Codable, Equatable, CaseIterable {}
extension AudioRoute: Codable, Equatable, CaseIterable {}
extension Bearing: Equatable, Codable {}
extension Identity: Equatable {}
extension TrackSnapshot: Equatable {}
extension CueKind: Equatable, Codable {}
extension SpeakerGuess: Equatable, Codable {}
extension TranscriptSegment: Equatable, Codable {}
extension Command: Equatable {}
extension Audience: Equatable {}
extension Utterance: Equatable {}
extension YesNo: Equatable {}
extension NameGuess: Equatable {}
extension ConsentState: Equatable {
    static func == (lhs: ConsentState, rhs: ConsentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.confirmingWithUser, .confirmingWithUser), (.listening, .listening), (.saving, .saving), (.declined, .declined): return true
        case let (.gathering(a), .gathering(b)): return a == b
        case let (.asking(a), .asking(b)): return a == b
        case let (.done(a), .done(b)): return a.id == b.id
        case let (.cancelled(a), .cancelled(b)): return a == b
        default: return false
        }
    }
}

