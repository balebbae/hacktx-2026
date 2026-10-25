# Devin session S1 — Skeleton (start immediately; every other session waits on this)

Platform: a macOS machine with Xcode 26.4+ (or Xcode 27). Repo: https://github.com/balebbae/hacktx-2026 (clone over HTTPS). Read `AGENTS.md` at the repo root in full before anything else: it holds the product rules, repo layout, working rules and the exact Swift contracts you must create. Push directly to `main` (this is the only session allowed to). Time budget: 90 minutes. Make decisions yourself; record assumptions in the commit message.

## Goal
Create the iOS app skeleton so that four other Devin sessions can work in parallel without touching the same files, and so the whole pipeline runs end-to-end in the iOS Simulator on fake data.

## Create
1. **Xcode project** `Familiar.xcodeproj` at the repo root: iOS app, SwiftUI, bundle id `com.familiar.hacktx`, deployment target iOS 18.0, Swift language mode 5, `SWIFT_STRICT_CONCURRENCY = minimal`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, portrait only, **synchronized folder groups** for `Familiar/` and `FamiliarTests/` (so adding files never edits `project.pbxproj`). Unit test target `FamiliarTests`; shared scheme `Familiar`.
2. **Package dependency:** ONNX Runtime SPM `https://github.com/microsoft/onnxruntime-swift-package-manager`, exact `1.24.2`, product `onnxruntime` linked to the app target (S2 needs it and may not edit the project). Verify that `import OnnxRuntimeBindings` compiles in a stub file; if the module name differs, read the package's test target and record the right name in the README.
3. **Secrets:** `Secrets.example.xcconfig` with empty `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_AGENT_ID`, `META_MODEL_API_KEY`, `MODAL_EMBED_URL`, `MODAL_KEY`, `MODAL_SECRET`; `.gitignore` for `Secrets.xcconfig`, `xcuserdata`, `DerivedData`, `*.pcm`. Wire the xcconfig to both configurations, pass values through Info.plist keys (`$(ELEVENLABS_API_KEY)` …) and expose them in `App/Secrets.swift` as optionals that are nil when empty.
4. **Info.plist:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSContactsUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`; `UIBackgroundModes` = `audio`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`, `processing`; `UISupportedExternalAccessoryProtocols` = [`com.meta.ar.wearable`]; `CFBundleURLTypes` with scheme `familiar`; an `MWDAT` dictionary `{AppLinkURLScheme: "familiar://", MetaAppID: "0", ClientToken: "0", TeamID: "$(DEVELOPMENT_TEAM)"}`. (The glasses SDK is added later by S6; these keys are harmless now.)
5. **Core:** `Familiar/Core/Contracts.swift` with the contracts from AGENTS.md **verbatim**. `Core/Models.swift`: `Codable` for `Person`, `FaceEmbedding`, `ConsentRecord`, `MeetingContext`; `FixtureManifest` for `fixtures.json`; `ScriptEvent` for `script.json`. `Core/EventBus.swift`: `final class EventBus<T: Sendable>` with `subscribe(bufferingPolicy:) -> AsyncStream<T>` (one continuation per subscriber, removed on termination) and `publish(_:)`, thread-safe with `OSAllocatedUnfairLock`. `Core/Phrasebook.swift`: every string from the Vocabulary section of AGENTS.md as functions (`Phrasebook.appeared(name:band:distance:)` …), plus `BearingBand.words` and `Distance.words`.
6. **Sources:** `VideoFileFrameSource` — plays an `.mp4`/`.mov` from the bundle or a URL with `AVAssetReader`, real-time pacing by presentation timestamps, loops, emits `Frame` (pixel format `kCVPixelFormatType_32BGRA`, timestamp = start + pts on the host clock, orientation `.up`, FOV from `fixtures.json` `fov` or the defaults 53 / 85). `PhoneCameraFrameSource` — `AVCaptureSession` 1080p30 back camera, portrait, `preferredVideoStabilizationMode = .off`, zoom 1.0, `alwaysDiscardsLateVideoFrames`, computes horizontal and vertical FOV from `activeFormat.videoFieldOfView` and the frame aspect (portrait: `hFOV = 2·atan(tan(longFOV/2)·W/H)`), exposes its running `AVCaptureSession` (needed later for `AVCaptureEventInteraction`) and a `setExposurePoint(_:)` hook. Compiles in the Simulator; emits no frames there.
7. **Fakes:** `Perception/ScriptedPerception.swift` implements `Perception`: reads `Resources/Fixtures/script.json` (array of `{t, event, name?, band?, distance?, count?, trackID?}`), emits events at those times on a host-clock timer, synthesizes plausible `TrackSnapshot`s and `preview` images; `currentTracks()` reflects the script; `bestEmbeddings` returns 3 fake 512-d unit vectors with `modelID "fake"` and a placeholder thumbnail; `requestBurst` / `assignIdentity` update state. Ship a default 60 s `script.json` that walks the demo: 3 unknowns → "Marcus" appears far right → approaching → arrived → left → reappears. `Speech/FakeTranscriber.swift` implements `Transcriber`: reads a `.txt` with lines `other: …` / `user: …`, emits one final `TranscriptSegment` every 2.5 s with the speaker from the prefix, keeps a 90 s window. `Voice/LogSpeaker.swift` implements `Speaker`: logs utterances with timestamps, optionally speaks through `AVSpeechSynthesizer` when a flag is on, returns a synthetic playback window (0.25 s per word), supports priority 0 interrupts.
8. **DI:** `App/Services.swift` — `@MainActor final class Services: ObservableObject` with protocol-typed properties (`frameSource`, `perception`, `audioInput`, `transcriber`, `speaker`, `cuePolicy`, `cueGate`, `peopleStore`, `contacts`, `nameExtractor`, `yesNo`, `consentFlow`, `commandSources`), a `Source` enum (`phone`, `glasses`, `fixture(name)`), and `make(source:)` which today wires the fakes plus a pass-through `CuePolicy` (every known event → one utterance via `Phrasebook`). `AppState`: `ChatterMode`, muted, selected source, user name ("Priya" default), place name.
9. **UI skeleton:** `HomeView` (status line, mode picker, Mute, "Who's here?", "Remember them", source picker, navigation to People / Settings / Judge view); `JudgeView` (preview from `snapshot.preview`, boxes drawn from `TrackSnapshot.faceBox` labelled "{name} {score}" for known / "person" for unknown, last 3 utterances from the speaker log, event log, the banner "Known people only. Strangers are 'a person'. Faces never leave this phone."); `SettingsView` and `PeopleView` placeholders. Every control has an accessibility label.
10. **Fixtures:** `Familiar/Resources/Fixtures/fixtures.json` using the schema below, listing the clips the team will add (missing files are fine), plus `script.json` and a placeholder `conversation.txt`.
11. **README.md** at the repo root: what Familiar is (two sentences), how to open/build/run, the `xcodebuild … test` command, how to add `Secrets.xcconfig` and fixtures, the module ownership table from AGENTS.md, and a note that InsightFace model weights are non-commercial research licensed.
12. **Tests:** `EventBusTests` (two subscribers both receive; a slow subscriber drops under `.bufferingNewest(1)`), `PhrasebookTests` (exact strings), `ScriptedPerceptionTests` (events fire in order with an injected clock), `FakeTranscriberTests` (window trimming), `VideoFileFrameSourceTests` (skips with a message when no fixture exists).

`fixtures.json` schema:
```json
{ "fov": {"horizontalDegrees": 53, "verticalDegrees": 85},
  "clips": [
    {"file": "enroll_marcus.mp4", "role": "enroll", "person": "Marcus"},
    {"file": "approach_marcus.mp4", "expectKnown": ["Marcus"], "expectEvents": ["knownApproaching", "knownArrived"], "maxUnknownEvents": 0},
    {"file": "leave_marcus.mp4", "expectKnown": ["Marcus"], "expectEvents": ["knownLeft"]},
    {"file": "strangers.mp4", "expectKnown": [], "maxKnownEvents": 0},
    {"file": "mixed.mp4", "expectKnown": ["Marcus"], "onlyKnown": ["Marcus"]},
    {"file": "conversation.mp4", "transcript": "conversation.txt", "expectName": "Marcus", "expectGoodbye": true},
    {"file": "yes_reply.mp4", "transcript": "yes_reply.txt", "expectYesNo": "yes"},
    {"file": "no_reply.mp4", "transcript": "no_reply.txt", "expectYesNo": "no"} ] }
```

## Non-goals
No real perception, audio, TTS, contacts, store or network code. No SwiftData. No packages beyond ONNX Runtime.

## Acceptance (paste the outputs into the final commit message)
- `xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test` passes.
- Launching in the Simulator with source = fixture shows the Judge view with scripted boxes appearing on schedule and a scrolling utterance log (`ScriptedPerception` → pass-through policy → `LogSpeaker`).
- `Contracts.swift` matches the AGENTS.md block character for character (diff it and say so).
- Pushed to `main`. Post a summary: what exists, what is stubbed, the ONNX Runtime module name.

## Definition of done for a human (5 minutes)
A fresh clone builds; on an iPhone the Judge view shows the fixture (or a black frame) with scripted boxes appearing on schedule.
