# Familiar — HackTX 2026

Social awareness for blind and low-vision people on Ray-Ban Meta Gen 2 glasses. The glasses are camera, mic and speaker; the iPhone does the thinking. Only people who agreed are ever recognized; strangers are "a person" and faces never leave the phone.

Start here:

- [FAMILIAR_MASTER_PLAN.md](FAMILIAR_MASTER_PLAN.md) — the brief: demo, scope, decisions, architecture, schedule, risks, sources.
- [AGENTS.md](AGENTS.md) — shared context that every Devin session reads automatically (product rules, repo layout, Swift contracts, conventions).
- [devin/](devin/) — one paste-ready prompt per Devin session: `01-skeleton` → `02-perception` ∥ `03-audio-speech-voice` ∥ `04-app-memory-consent` ∥ `09-modal-embedding-endpoint` ∥ `06-glasses-source` → `05-integration-demo` → `07`, `08` (stretch).
- [TEAM_CHECKLIST.md](TEAM_CHECKLIST.md) — the human track with clock times, including the fixture-clip shooting script.
- [docs/DESIGN_SPEC.md](docs/DESIGN_SPEC.md) — the visual and interaction design spec (ivory canvas, pill controls, Mimo the companion). The `sahas` branch implements it with the libraries.dev SwiftUI kits (`BotAvatarsKit`, `ThinkingOrbsKit`, `VoiceGlowKit`).

## Build and run

Requirements: Xcode 26.4 or newer (the glasses SDK needs it; the rest of the app builds on 26.x), iOS 18+ device or an iPhone 17 simulator.

```bash
cp Secrets.example.xcconfig Secrets.xcconfig          # fill in keys; never commit this file
open Familiar.xcodeproj                                 # scheme "Familiar", any iPhone simulator or your phone
xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

On a device: select your personal team under Signing & Capabilities once; the bundle id is `com.familiar.hacktx`. In the Simulator the app defaults to the fixture source (`mixed.mp4`) with `ScriptedPerception`, `FakeTranscriber` and `LogSpeaker` (Apple voice), so the Judge view shows scripted boxes and spoken cues without any hardware.

### Design branch (`sahas`)
The `sahas` branch carries the full SwiftUI redesign (docs/DESIGN_SPEC.md, docs/DESIGN_SYSTEM.md, docs/UI_CONTRACTS.md). Build notes specific to it:

- **Fonts.** Plus Jakarta Sans Regular/Medium/SemiBold/Bold live in `Familiar/Resources/Fonts/` and are registered in `Familiar/Info.plist` under `UIAppFonts`. Every label goes through `FamiliarType.*(scale)`; if the fonts ever go missing from the bundle, `FamiliarFont` falls back to the rounded system face instead of Times New Roman.
- **libraries.dev kits.** Six products of the `Libraries.dev` package (branch `main`, pinned in `Package.resolved`) are linked to the app target in `project.pbxproj`: `BotAvatarsKit` (Mimo), `ThinkingOrbsKit` (status orb), `VoiceGlowKit` (consent card glow), `BorderBeamKit` (nearby card and consent card beams), `MetalFxKit` + its dependency `MagnetKit` (the liquid-metal "Who's here?" ring). Xcode resolves them on first open; if resolution fails, File → Packages → Resolve Package Versions. The MetalFx shaders compile as part of the normal build.
- **iOS 18 APIs.** `MeshGradient`, `Color.mix`, `Group(subviews:)` and `onScrollPhaseChange` are used unguarded because `IPHONEOS_DEPLOYMENT_TARGET` is 18.0. The one iOS 26 API (`glassEffect` on the pager's edge strips) sits behind `#if compiler(>=6.2)` + `if #available(iOS 26, *)`, so Xcode 16 builds the material fallback and Xcode 26 the liquid glass.
- **Launch arguments.** `--onboarding` replays the first-launch flow; `--glasses` opens the glasses registration directly and boots the pipeline at once; `-demoConsentCard` shows the consent card over the tabs for screenshots.
- **First launch.** Onboarding runs before the pipeline boots, so no camera or microphone prompt appears over the Welcome page; the permissions checklist (`ReadinessView`) is the Privacy page's Continue step and reappears once on Today if it was skipped.
- **Snapshots.** `SNAPSHOT_DIR=$PWD/docs/snapshots xcodebuild … -only-testing:FamiliarTests/SnapshotRenderTests test` renders Welcome, Today, Room radar, People, consent card, Accessibility settings and Mimo at the balanced and severe vision profiles.
- **What was not possible on the design machines.** The branch was written on Macs without an iOS SDK: every file passes `xcrun swiftc -parse` (Swift 5 and 6 modes) and the kit signatures were checked against the pinned libraries.dev sources, but the first real `xcodebuild` happens on your Mac. If something fails to type-check, the usual suspects are listed in docs/HANDOFF.md under "Design branch (sahas)".

### Secrets
`Secrets.xcconfig` → Info.plist keys → `Familiar/App/Secrets.swift` (nil when empty). Keys: `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_AGENT_ID`, `META_MODEL_API_KEY`, `MODAL_EMBED_URL`, `MODAL_KEY`, `MODAL_SECRET`. URLs in xcconfig need `$()/` in place of `//` (`https:$()/$()/...`).

### Fixtures
`Familiar/Resources/Fixtures/`: `*.mp4` clips (720×1280), `fixtures.json` with per-clip expectations, `*.txt` transcripts for `FakeTranscriber`, `script.json` for `ScriptedPerception`. Missing clips make the related tests skip, never fail.

## Project layout and ownership

The Xcode project uses **synchronized folder groups** (`Familiar/`, `FamiliarTests/`): adding a file never edits `project.pbxproj`. The project was generated once with XcodeGen from `project.yml`; after S1, `project.pbxproj` is the source of truth (S6 adds the glasses package to it directly). Do not re-run `xcodegen` unless you are prepared to re-add later package changes.

| Folder | Owner | Contents |
|---|---|---|
| `Familiar/App` | S1 / S5 | `FamiliarApp`, `AppCoordinator`, `AppState`, `Services` (DI), `Secrets`, `ReadinessView` |
| `Familiar/Core` | S1 (S5/S6 may extend) | `Contracts.swift` (verbatim from AGENTS.md), `Models`, `EventBus`, `Phrasebook` |
| `Familiar/Sources` | S1, S6 | `VideoFileFrameSource`, `PhoneCameraFrameSource`, `GlassesFrameSource` |
| `Familiar/Perception` | S2 | detector, tracker, aligner, embedders, matcher, pipeline (`ScriptedPerception` is S1's fake) |
| `Familiar/Audio`, `Speech`, `Voice`, `Flows/RollCall` | S3 | engine, transcriber, wake word, TTS, cue policy and gate |
| `Familiar/Memory`, `Flows`, `Intelligence`, `UI` | S4 | people store, contacts, consent flow, command router, name extraction, every screen |
| `modal/` | S9 | Modal twin of the embedding model |
| `FamiliarTests` | everyone | one test file per module |

ONNX Runtime is linked through the Swift package `onnxruntime-swift-package-manager` 1.24.2; the module to import is `OnnxRuntimeBindings` (see `Familiar/Perception/ORTSmokeTest.swift`).

## Licenses
InsightFace model weights (`w600k_mbf.onnx`, buffalo_sc) are released for non-commercial research use only; this hackathon build uses them under that license. Everything else is MIT unless noted in the dependency.
