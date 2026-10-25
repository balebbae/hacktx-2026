# Devin session S5 — Integration and demo build (branch `feat/integration` → `main`; starts when the S2, S3, S4 PRs exist)

Read `AGENTS.md` and the open PR descriptions. You may edit anything, including `Core/*` and the project, but keep contract changes additive and tell the other sessions what changed (comment on their PRs). Humans will be testing on two iPhones and posting issues into this session; fix them here. Time budget: 4 hours.

## Goal
Merge `feat/perception`, `feat/voice`, `feat/app` (plus `feat/modal` and `feat/glasses` when ready) into one app that runs the full demo on a fixture clip in the Simulator and on an iPhone with the glasses as a Bluetooth headset, and produce the hand-off documents.

## Steps
1. Merge the branches into `feat/integration` (resolve conflicts; `project.pbxproj` conflicts should come only from S6's package addition — keep both sides). Build and tests green.
2. **`Services.make(source:)`** wires the real implementations: `PhoneCameraFrameSource` / `VideoFileFrameSource` / `GlassesFrameSource` (if present) → `PerceptionPipeline` with `OnDeviceEmbedder` (or `ModalEmbedder` by Settings) → `CuePolicy` → `CueGate` → `Speaker` (ElevenLabs + Apple) → `AudioEngineController`; `SpeechAnalyzerTranscriber` with fallbacks fed by `EngineAudioInput`; `LoudnessSplit`; `WakeWord` + `CommandParser` + volume buttons → `CommandRouter`; `ConsentFlow` with `CompositeNameExtractor` and the `NameGuessCache` loop; `JSONPeopleStore` as the `GalleryProvider`; `ContactsBridge`; `MeetingContext`. In the Simulator the source defaults to fixture with `FakeTranscriber`; on a device to the phone camera with the real transcriber.
3. Lifecycle: audio starts at launch; the frame source starts when Home appears; `UIApplication.shared.isIdleTimerDisabled = true`; the app stays in the foreground; on backgrounding stop the phone camera but keep audio.
4. Readiness gating and permission order; speech-asset download UX; Foundation Models availability text.
5. Judge view final polish per the S4 list, including the banner; Demo controls work.
6. Calibration hooks: live threshold slider; editable distance bin thresholds and FOV; loudness calibration. Write **`docs/CALIBRATION.md`**: set T from the live scores (same person should sit well above T, strangers below T − margin), distance bins from `distance_calibration.mp4` or tape marks at 1 / 2 / 3 m, FOV measurement for the glasses stream (stand a person at a known angle), loudness split.
7. **`docs/HANDOFF.md`**: build to a device (personal signing team), first-run permission order, both audio routes, how to switch sources, known issues, and exactly what to test in which order. **`docs/DEMO_SCRIPT.md`**: the five demo steps with the trigger for each and the expected utterances.
8. Fix what the humans report. Keep the PRs small and merge to `main` often.

## Acceptance
Simulator, source = fixture: the full chain runs unattended, twice in a row — fixture frames → real perception (gallery built from `enroll_marcus`) → cues spoken through the Apple voice → "Remember them" with `FakeTranscriber` → person saved → contact created through the fake bridge. `xcodebuild … test` green on `main`.

## Definition of done for a human (5 minutes, on device)
Demo steps 1–4 pass twice in a row at the real table on Route A; the Readiness screen is all green on both demo phones; a teammate gets from a fresh clone to a running app in ≤ 10 minutes by following HANDOFF.md.
