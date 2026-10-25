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
- The iPhone 17 Simulator on Xcode 26.6 cannot create Vision inference contexts ("Could not create inference context"): face detection and scene awareness return nothing there, and the 7 Vision fixture tests skip with that reason. Run them on a device.
- Hazard thresholds (stairs label votes, obstacle time-to-contact) are uncalibrated defaults; see docs/CALIBRATION.md → Hazards.
- The ElevenLabs agent must allow the **Text only** override (docs/AGENT_SETUP.md step 6), or the session fails to start and the Judge view shows `connect failed`.

## What is wired on main (S5 pass)
- `Services.make` builds the real modules: `PerceptionFactory` (on-device `w600k_mbf.onnx`, Modal fallback when `MODAL_*` keys are present), `AudioFactory.makeEngine` (started once; the glasses streaming flag drives `glassesStreamActive`), `VoiceFactory.makeSpeaker` (ElevenLabs over the engine, Apple fallback; Settings → Voice can force Apple or the log speaker), `VoiceFactory.makeCuePolicy`, `SpeechFactory.makeTranscriber` on device (SpeechAnalyzer → SFSpeech) and `FakeTranscriber(conversation.txt)` in the Simulator, wake-word `CommandSource`.
- `FlowRuntime` (S4) builds the consent flow, command router, `JSONPeopleStore` and `CNContactsBridge` on top of those services.
- Demo controls → "Scripted perception" (UserDefaults `useScriptedPerception`) swaps the pipeline for `ScriptedPerception` + `script.json`; use it if the camera path misbehaves at the table.
- `Secrets.xcconfig` also carries `DEVELOPMENT_TEAM` for device signing; the Modal URL is written `https:$()/$()/host`.
- Tests: `AppCoordinator.isRunningTests` keeps the live pipeline off while the app is only the XCTest host. 150 tests, 2 skipped (unsigned DAT mock, live ElevenLabs prewarm) on `main`.
- Still human-only: real glasses stream, A2DP/HFP route switching, SpeechAnalyzer asset download, Contacts/Location prompts, Vision landmarks on device (Simulator falls back to rectangle alignment).

## Design branch (sahas)
The `sahas` branch is the full SwiftUI redesign: ivory canvas, white 26 pt cards, pill controls, Plus Jakarta Sans SemiBold everywhere, one luminous object per screen (Mimo or the blue→orange→purple aurora), and a vision profile (Balanced · Low vision · Severe · Non-visual) that scales every size, weight, icon and hit target. Contracts and ownership: `docs/UI_CONTRACTS.md`; tokens and components: `docs/DESIGN_SYSTEM.md`.

### Screens
- **Onboarding** (`Familiar/UI/Onboarding/`, swiped in `GlassEdgePager`): Welcome (Mimo, "Because everyone deserves to feel seen.", motto) · What Familiar can and cannot do · How would you like Familiar to communicate? (vision profile picker with live preview and a sample cue) · How privacy works (Continue opens the permissions checklist) · Connect glasses / Continue. `@AppStorage("onboardingDone")`; the pipeline boots only afterwards.
- **Today** (`HomeView`): Mimo on the aurora, headline and status line, the one `MetalFx` "Who's here?" ring, Pause / Remember them, cue-level `SlidingPillSegment`, nearby card with a `borderBeam` for six seconds after a person cue, consent status, last error with `errorShake`.
- **Room** (`JudgeView.swift`, `Familiar/UI/Room/`): counts with `NumberPop`, **RoomRadarView** (half-disc, five bands, three rings, named mint dots for known people, hollow dots for strangers, one VoiceOver sentence), `RoomPeopleList`, camera stage with HUD, diagnostics folded. Everything is driven by frames that are actually arriving (`services != nil && fps > 0`).
- **People** (`PeopleView`, `Familiar/UI/People/`): cards with photo or `Monogram`, search, All / Recent chips, **Add someone** `GooeyMenu` (Ask them out loud → consent flow; Show invitation → explains the tag flow is coming), Person detail (Call · Text · Where we met · Remove), **PlacesMapView** (MapKit map of where people said yes, one annotation per person, list underneath), `InvitationSheet`.
- **You** (`Familiar/UI/You/`, `SettingsView`, `DemoControlsView`): hub card, Accessibility (vision profile, haptics, speech rate/volume keys, keep cue text on screen, iOS settings mirror), Voice and cues, Privacy dashboard ("Your people. Your control.", counts, map link, Remove everyone), Demo controls.
- **Consent card** (`ConsentCardView`): `VoiceGlow` at the bottom while listening, `borderBeam` on the question, `ParticleBurst` on Yes. **Cue toast** (`MainTabView`): every spoken cue to the wearer as text for 5 s (or until the next one), from `LogSpeaker` entries and `VoiceSpeaker.onSpoken`.
- **Motion library** (`Familiar/UI/Motion/`): `GlassEdgePager`, `CueToast`, `ShimmerText`, `NumberPop`, `ParticleBurst`, `SlidingPillSegment`, `GooeyMenu`, `errorShake`, `skeletonReveal`, `liftOnPress`, `cardResize`, `tilt3D`, `FamiliarHaptics` (Core Haptics, UserDefaults `hapticsEnabled`).

### Kits (libraries.dev, pinned in Package.resolved)
`BotAvatarsKit` (Mimo = `BotAvatar(type: .blob, face: .mouth)`), `ThinkingOrbsKit` (`ThinkingOrb` in `MimoStatusLine`), `VoiceGlowKit` (consent card), `BorderBeamKit` (`.borderBeam` on the nearby card and consent card), `MetalFxKit` + `MagnetKit` (`MetalFx(variant: .button)` on Today). All six are linked in `project.pbxproj`; `docs/LIBRARIES_DEV_API.md` has the signatures as read from the pinned revision.

### Known risks on this branch
- Written without an iOS SDK: syntax-checked with `xcrun swiftc -parse` only; the Motion files were additionally type-checked against the macOS SDK. The first `xcodebuild` is the real test. If it fails, look first at: `AttributedString.accessibilitySpeechAnnouncementPriority` (OnboardingFlow), `Group(subviews:)` / `onScrollPhaseChange` (GlassEdgePager), `Color.mix(with:by:in:)` and `MeshGradient` (AuroraBackground), `Map`/`Annotation` (PlacesMapView), `AVAudioApplication` (ReadinessView).
- `speechRate` / `speechVolume` are now read by the voice (`SpeechPreferences` in `Voice/VoiceContracts+.swift`): `AppleTTS` and the Simulator `LogSpeaker` scale `AVSpeechUtterance.rate`, `ElevenLabsTTS` sends `voice_settings.speed` (clamped 0.7–1.2; a non-1.0 speed gets its own cache key), and `VoiceSpeaker.volumeProvider` applies the volume as a gain. A missing key means unchanged, so tests and fresh installs are unaffected.
- The "Speaking first" toggle is read by `FamiliarCuePolicy` through `VoiceFactory.makeCuePolicy()` (default on, as before). Wave and smile say "Coming later" because nothing detects them yet.
- Both speaker feeds now land on `AppState.spokenCues` (from `MainTabView`), so Today's Mimo speaking pose, the nearby card's beam and Room's cue ticker work with `VoiceSpeaker` on a device, not only with the Simulator's `LogSpeaker`. The cue toast offers "Repeat", which re-speaks that utterance through the live speaker (`Command.repeatLast` only remembers the router's own answers).
- Pause is reachable from a fixed action everywhere: the volume button can be set to "Pause cues" (You → Voice and cues), and Room has a Pause / Resume chip in its header.
- Room cards offer Details (pushes `PersonDetailView`); Today's nearby card offers Call when the person has a phone number. Room's counts and list show a `skeletonReveal` only between the pipeline starting and the first frame (at most 6 s), then the honest "Room awareness paused." line when frames never come.
- Welcome has "Explore a demo" (sets the source to the bundled conversation clip and finishes setup; Today's chip reads "Demo clip"). The onboarding sample cue says it uses the iPhone's voice until setup finishes. You → Accessibility has Mimo visibility (full, compact, hidden) for Today and Room.
- `AppCoordinator.fps` never decays once frames stop mid-session, so "Waiting for the camera" cannot notice a stalled source after the first frames.
- `GlassEdgePager`'s liquid-glass edge strips need Xcode 26 (`#if compiler(>=6.2)`); Xcode 16 builds a material strip instead.

## S7: who is talking to me (merged from PR #6)
- `Familiar/Perception/ActiveSpeaker.swift`: VAD `.other` speech + mouth-openness variance over 1 s (threshold 0.0015, sustained 0.6 s) on known, facing tracks only. One `speakingStarted` per person per track-session, 5 min reset, 2 s cooldown between speakers, never for unknown tracks. Wired in `Services.make` on the real pipeline; `ScriptedPerception` scripts the event itself.
- Cue "{Name}." is priority 1, no earcon, played at -6 dB (`SpeakerVolumeHint`).
- Simulator cannot exercise it (Vision landmarks fall back to the box, so `mouthOpenness` is nil); 12 unit tests cover the detector. On the iPhone: Marcus talks -> "Marcus." once; stranger talks -> nothing; wearer talks -> nothing.
