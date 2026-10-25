# Familiar — shared context for every Devin session (read fully before acting)

## What this is
Familiar is an iOS app (SwiftUI) for blind and low-vision people wearing Ray-Ban Meta Gen 2 glasses. The glasses are camera, mic and speaker; the iPhone does the thinking. It tells the wearer which **consented** people are around ("Marcus, ahead, close."), who is approaching or leaving, warns about hazards ("Stairs ahead.", "Obstacle ahead."), keeps an always-on assistant that follows the conversation, and it remembers a new person only after that person says "yes" out loud or taps YES. Hackathon demo for HackTX 2026 (submission Sun Oct 25 11:30 AM CDT, judging 2–5 PM, table-side, 2–4 people in view). Not production code: optimise for a working demo, honest fallbacks, and code a human can run on an iPhone in five minutes.

## Non-negotiable product rules (they also appear on the judge-view banner)
1. Only people who agreed are ever recognized. A stranger is "a person" or "someone": never a name, never a description, never stored.
2. Agreement happens on the other person's side (their spoken yes or their tap). The wearer cannot add someone unilaterally. When Familiar notices a conversation with someone it does not know, it asks the wearer "Should I add this person to your contacts?"; if the wearer agrees, the wearer asks the person in their own words and only that person's yes (or tap) saves anything; then the name is asked if it was not caught, "I'm going to scan your face.", scan, save. The other person may also enroll themselves by picking up the phone ("Introduce yourself" button or an NFC tag / `familiar://introduce`) and tapping YES on their own. The assistant (LLM) never decides consent.
3. Faces, embeddings, consent clips and camera frames live only on this phone; scene and hazard detection runs on the device (Apple Vision). Cloud services receive **text only**: TTS strings, the transcript and the people/scene summary for the ElevenLabs agent (strangers only as a count), transcript snippets for name extraction. One exception: the optional Modal embedding fallback receives aligned 112×112 face crops and discards them.
4. Anyone can be removed. Removal deletes everything: the record, thumbnail, consent clip and the iOS contact the app created.
5. The glasses' recording LED stays on; never hide that the camera is on.
6. Never speak for the user and never send a message on their behalf: open the dialer or Messages and let them act. Never keep audio beyond a rolling 90 s transcript in RAM and the few-second consent clip.
7. No mood reading. Cues are limited to presence, approach/leave, speaking first (stretch), wave/smile (stretch).
8. Mistaken identity is worse than no identity. When unsure, say "someone".
9. Speak when it helps, never narrate. Hazards (stairs, escalators, crosswalks, something in the walking path) are said immediately; everything else is 3–6 words and only when it matters; the assistant answers when addressed or clearly useful and otherwise stays silent. The wake word is optional (the assistant listens all session). No app utterance may contain the word "Familiar".

## Never build
NFC-tag enrollment that bypasses the other person's own tap-to-consent, a web enrollment page, notifications to known people, voice/speaker identification, cloud vision for scene or hazard detection (frames never leave the phone), any server-side storage, SwiftData, Combine-based plumbing, any cloud image call outside the Modal toggle, an ElevenLabs **voice** session (it opens Bluetooth HFP, which ends the glasses camera stream; the agent is text-only), describing strangers in scene output.

## Repo layout (Xcode synchronized folder groups: adding a file never edits project.pbxproj)
```
AGENTS.md · README.md · Secrets.example.xcconfig    (real Secrets.xcconfig is git-ignored)
Familiar.xcodeproj         Swift 5 mode · SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated · iOS 18 target · ORT package pinned 1.24.2
Familiar/App               FamiliarApp, AppState, Services (DI), Secrets, ReadinessView
Familiar/Core              Contracts.swift, Models.swift, EventBus.swift, Phrasebook.swift        (S1 writes; S5/S6 may extend)
Familiar/Sources           PhoneCameraFrameSource, VideoFileFrameSource, GlassesFrameSource (S6)
Familiar/Perception        FaceDetector, FaceTracker, FaceAligner, OnDeviceEmbedder, ModalEmbedder, Matcher, Spatial, Trajectory, PerceptionPipeline, ScriptedPerception, SceneAwareness (on-device hazards + scene)
Familiar/Audio             AudioEngineController, EngineAudioInput, RingBuffer, LoudnessSplit (+ GlassesStreamAudioInput S6, LiveKitTapAudioInput S8)
Familiar/Speech            Transcriber (SpeechAnalyzer; SFSpeech fallback), FakeTranscriber, WakeWord, CommandParser
Familiar/Voice             Speaker, ElevenLabsTTS, AppleTTS, PhraseCache, Earcon, CuePolicy, CueGate, AgentSession (always-on, text-only)
Familiar/Memory            JSONPeopleStore, ContactsBridge, MeetingContext
Familiar/Flows             ConsentFlow, CommandRouter, RollCall
Familiar/Intelligence      NameExtractor (Regex, FoundationModels, MetaModelAPI), YesNoClassifier, MetaModelClient
Familiar/UI                HomeView, PeopleView, PersonDetailView, SettingsView, JudgeView, ConsentCardView, DemoControlsView
Familiar/Resources         models/w600k_mbf.onnx · Fixtures/ (clips, transcripts, fixtures.json, script.json) · phrases.json
FamiliarTests              one test file per module
modal/embed_server.py      S9 · docs/HANDOFF.md · docs/CALIBRATION.md · docs/DEMO_SCRIPT.md
```

## Working rules for parallel sessions
- **Only S1, S5 and S6 edit `Familiar/Core/*`, `project.pbxproj`, `Package.resolved` or `Info.plist`.** Other sessions add new types in `<Module>Contracts+.swift` inside their own folder and never change an existing contract signature. If a contract is wrong, work around it locally and say so in the PR description.
- Branch `feat/<module>`; PR to `main`; small commits. PR description = what works, what is stubbed, exact steps for a human to verify on an iPhone in under five minutes, and the pasted summary of the test run.
- Build and test (Simulator): `xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test`.
- Toolchain: Swift 5 language mode, strict concurrency minimal, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. Deployment target iOS 18; iOS 26 APIs behind `#if canImport(FoundationModels)` / `#available(iOS 26, *)`. The glasses SDK (S6) needs Xcode 26.4+ or Xcode 27 (`xcodebuild -version`; set `DEVELOPER_DIR` if needed).
- Timestamps are host-clock seconds (`CACurrentMediaTime()`): frames via `CMTimeGetSeconds(pts)` mapped to host time, audio via `AVAudioTime.seconds(forHostTime:)`. Everyone compares; only the Audio module converts.
- Streams: every producer exposes `func subscribe() -> AsyncStream<T>` with one continuation per subscriber. Buffering: frames `.bufferingNewest(1)` (never pin pixel buffers), audio `.bufferingNewest(64)`, events `.unbounded`.
- Sync getters (`gallery()`, `currentTracks()`, `bestEmbeddings()`, `recentSegments()`) serve a snapshot protected by `OSAllocatedUnfairLock`. `PeopleStore` is `@MainActor` and republishes a `Gallery` value on every change.
- Secrets: `Secrets.xcconfig` (copy from `Secrets.example.xcconfig`) → Info.plist keys → `Secrets.swift`. Never hardcode or commit keys. In Devin, keys are env vars from the secrets store; write them into the local `Secrets.xcconfig` only.
- The Simulator has no camera, no SpeechAnalyzer, no Foundation Models and no glasses. Every feature must be exercisable with `VideoFileFrameSource` (fixtures), `ScriptedPerception`, `FakeTranscriber`, `LogSpeaker`, and a `FakeEmbedder`. Assume Apple on-device speech and LLM APIs return "unavailable" in the Simulator and prove the fallback paths instead.
- Fixtures live in `Familiar/Resources/Fixtures/` with `fixtures.json` (expected names, events, counts, extracted name, yes/no) and `*.txt` transcripts (`other: …` / `user: …` lines) for `FakeTranscriber`. If a fixture is missing, skip that test with a clear message; never fail the build on missing media.
- Dependencies, pinned: ONNX Runtime SPM 1.24.2 (added by S1); Meta Wearables DAT 1.0.1 (S6); ElevenLabs Swift SDK 3.4.0 (S8). Nothing else.
- VoiceOver: every control has a label and hint; no colour-only state; Dynamic Type; test with the Accessibility Inspector.
- Make decisions yourself; do not stop to ask. Record assumptions in the PR.

## Contracts (Familiar/Core/Contracts.swift) — verbatim, do not change signatures
```swift
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
final class CueGate { var muted: Bool; var consentActive: Bool; var userSpeaking: Bool; func admit(_ u: Utterance) -> Bool /* priority 0 always */ }

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
```
Models (`Core/Models.swift`) hold `Codable` conformances, `Equatable` where useful, and the JSON `fixtures.json` / `script.json` schemas. `EventBus` is a generic multi-subscriber fan-out used by every `subscribe()`.

## Vocabulary (Core/Phrasebook.swift; every spoken string comes from here)
bands: ahead · left · right · far left · far right — distances: close · medium · far
appeared "{Name}, {band}, {distance}." · approaching "{Name}, coming from your {left|right}." / "{Name}, coming toward you." · arrived "{Name}, next to you." · left "{Name} left." · unknown close (chatty only) "Someone close, on your {left|right}." / "Someone close, ahead." · speaking "{Name}."
roll call: known left→right "{Name}, {band}, {distance}." then "{k} other people." / "One other person." / "No one else."; no known "No one I know. {k} people."; empty "I don't see anyone."
consent: "Should I add this person to your contacts?" (to the wearer) · card "Do you want to be added to {UserName}'s contacts?" · "I'm going to scan your face." · "Could you look toward me for a second?" · "{UserName} would like to recognize you next time you meet. Okay to remember your face{, Name}?" · "Sorry, was that a yes?" · "What should I call you?" · "Saved. {Name} is in your contacts." · "Okay, nothing saved." · "They seem to have left. Nothing saved."
hazards (priority 0, immediately): "Stairs ahead." "Escalator ahead." "Crosswalk ahead." "Obstacle ahead." · surroundings on request: hazards, then roll call, then "{Place}." "{Object}, {object}." / "Nothing I can name." · place change (chatty only): "{Place}."
commands: "Quiet mode." "Normal mode." "Chatty mode." "Muted." "Unmuted." "Calling {Name}." "Opening a message to {Name}." "I don't know anyone called {X}." "I don't see {Name}." "Sorry, I didn't get that."

## External services (text only leaves the phone)
- ElevenLabs TTS: `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=pcm_16000`, header `xi-api-key`, body `{"text","model_id":"eleven_flash_v2_5","voice_settings":{"stability":0.5,"similarity_boost":0.75,"speed":1.0},"previous_text":"…"}` → raw 16-bit LE mono 16 kHz PCM. Cache to disk by SHA-256(voice|model|text). Apple `AVSpeechSynthesizer` fallback after 1.2 s without a first byte.
- ElevenLabs agent (Conversational AI, **text-only** WebSocket): public agent by id, private agent via `GET /v1/convai/conversation/get-signed-url?agent_id=` with `xi-api-key`. Kept open all session, reconnects with backoff. Wearer's final transcript segments go as `[overheard] …` user turns (agent replies `SKIP` unless useful), wake-word phrases as `[to you] …`, other people's speech and the visible-now/around summary as contextual updates. Replies are spoken by our `Speaker` (Route A, glasses A2DP). Nothing is sent and nothing is spoken while a consent flow runs. Setup: docs/AGENT_SETUP.md.
- Meta Model API: `POST https://api.meta.ai/v1/chat/completions`, `Authorization: Bearer $META_MODEL_API_KEY`, model `muse-spark-1.3` (never the `-contributor` tier), `reasoning_effort` `low`/`minimal`, `response_format` json_schema strict, `max_completion_tokens` 300–500, `prompt_cache_key`. 1–3 s latency: never on the hot path.
- Modal: `POST $MODAL_EMBED_URL` with headers `Modal-Key`/`Modal-Secret`, body `{"image_b64": "<112×112 JPEG>"}` → `{"embedding":[512 floats],"model":"w600k_mbf"}`; `GET` health endpoint.
