# Familiar hand-off (fresh clone to running app in 10 minutes)

## Build to a device
1. Xcode 26.4 or newer (26.6 was used for development; the glasses SDK needs ≥ 26.4). `git clone https://github.com/balebbae/hacktx-2026 && cd hacktx-2026`.
2. `cp Secrets.example.xcconfig Secrets.xcconfig` and fill in `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` (optional), `META_MODEL_API_KEY`, and the Modal trio if you have proxy-auth tokens. Write URLs as `https:$()/$()/host` (xcconfig treats `//` as a comment).
3. `open Familiar.xcodeproj` → target Familiar → Signing & Capabilities → your personal team. Bundle id `com.familiar.hacktx`. Plug in the iPhone, pick it as destination, Run. On the phone: Settings → General → VPN & Device Management → trust the developer.
4. Simulator: `xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test` must be green; the app defaults to the `mixed` fixture with fake perception, fake transcriber and the Apple voice.

## First run on the phone (permission order)
Camera → Microphone → Speech recognition (only if the iOS 18 fallback is used) → Contacts → Location. The Readiness screen walks through them and shows the iOS 26 speech asset download, Foundation Models availability, keys present, audio route, embedding model loaded, glasses registration. Do this on Wi-Fi before 7 AM so the speech assets are downloaded.

## Audio routes (Settings → Audio route)
- **Route A (default)**: phone mic + glasses A2DP. Keeps HFP closed, which the glasses stream requires.
- **Route B**: glasses HFP mic + speaker. Refused while a glasses stream is active (opening HFP ends the stream).
- Phone only: no Bluetooth.
Consent questions (`audience: otherPerson`) always come out of the phone loudspeaker.

## Switching sources (Home → Source)
Phone camera · Glasses · Fixture: <clip>. Glasses: Meta AI app → Settings → App Info → tap version 5× → Developer Mode → Familiar "Connect glasses" → approve in Meta AI → wait up to ~15 s for frames. Restart Familiar before each long glasses session (Classic transport leaks ~4 MB/min).

## Test order at the table
1. Readiness all green on both phones.
2. Fixture source in the Judge view: scripted boxes and cues appear.
3. Phone camera: a teammate at 1–2 m shows as "person"; Who's here? counts correctly.
4. Remember them with a teammate: question from the phone speaker + card → "yes" → "Saved…" → Contacts.app has them with a photo and no note.
5. Walk away / come back: approaching and next-to-you cues; strangers produce nothing.
6. Remove from People: row, files and the contact are gone.
7. Glasses: repeat 3–5 with the glasses stream and A2DP cues.

## Known issues
- `approach_marcus.mp4` is only 2.9 s; `no_reply.mp4` and `distance_calibration.mp4` were never recorded (tests skip).
- Modal proxy-auth tokens must be created by a human in the Modal dashboard; the on-device embedder is the primary path.
- Filled in by S5 with whatever the integration pass finds.

## What is wired on main (S5 pass)
- `Services.make` builds the real modules: `PerceptionFactory` (on-device `w600k_mbf.onnx`, Modal fallback when `MODAL_*` keys are present), `AudioFactory.makeEngine` (started once; the glasses streaming flag drives `glassesStreamActive`), `VoiceFactory.makeSpeaker` (ElevenLabs over the engine, Apple fallback; Settings → Voice can force Apple or the log speaker), `VoiceFactory.makeCuePolicy`, `SpeechFactory.makeTranscriber` on device (SpeechAnalyzer → SFSpeech) and `FakeTranscriber(conversation.txt)` in the Simulator, wake-word `CommandSource`.
- `FlowRuntime` (S4) builds the consent flow, command router, `JSONPeopleStore` and `CNContactsBridge` on top of those services.
- Demo controls → "Scripted perception" (UserDefaults `useScriptedPerception`) swaps the pipeline for `ScriptedPerception` + `script.json`; use it if the camera path misbehaves at the table.
- `Secrets.xcconfig` also carries `DEVELOPMENT_TEAM` for device signing; the Modal URL is written `https:$()/$()/host`.
- Tests: `AppCoordinator.isRunningTests` keeps the live pipeline off while the app is only the XCTest host. 150 tests, 2 skipped (unsigned DAT mock, live ElevenLabs prewarm) on `main`.
- Still human-only: real glasses stream, A2DP/HFP route switching, SpeechAnalyzer asset download, Contacts/Location prompts, Vision landmarks on device (Simulator falls back to rectangle alignment).

## S7: who is talking to me (merged from PR #6)
- `Familiar/Perception/ActiveSpeaker.swift`: VAD `.other` speech + mouth-openness variance over 1 s (threshold 0.0015, sustained 0.6 s) on known, facing tracks only. One `speakingStarted` per person per track-session, 5 min reset, 2 s cooldown between speakers, never for unknown tracks. Wired in `Services.make` on the real pipeline; `ScriptedPerception` scripts the event itself.
- Cue "{Name}." is priority 1, no earcon, played at -6 dB (`SpeakerVolumeHint`).
- Simulator cannot exercise it (Vision landmarks fall back to the box, so `mouthOpenness` is nil); 12 unit tests cover the detector. On the iPhone: Marcus talks -> "Marcus." once; stranger talks -> nothing; wearer talks -> nothing.
