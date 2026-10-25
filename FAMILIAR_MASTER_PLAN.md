# Familiar — master plan (HackTX 2026, demo in under 24 hours)

Social awareness for blind and low-vision people on Ray-Ban Meta Gen 2 glasses. This is the single brief for the humans and for Devin. Written Sat Oct 24 2026 (~8 PM CDT) against verified documentation (sources at the end). `AGENTS.md` at the repo root is what every Devin session reads automatically; `devin/01…09` are the per-session prompts; `TEAM_CHECKLIST.md` is the human track.

## 1. Read this first

- **Hard stops.** Devpost submissions close **Sun Oct 25, 11:30 AM CDT** (demo video, public git repo, AI coding tools disclosed → disclose Devin). Judging **2–5 PM Welch Hall**, table-side. Pitching 5:30 PM.
- **Target track.** Meta is title sponsor. Its track "Bringing People Closer Together with AI" judges human connection, how essential and integrated the AI is, originality and the working demo. Familiar is built for exactly that and runs on Meta glasses with the Meta Model API. Best Hardware is the second track.
- **Your Meta credits are on the Meta Model API** (`api.meta.ai`, Muse models), not the Llama API, which Meta retired on July 6 2026. The plan uses `muse-spark-1.3` on the Standard tier. The cheaper "contributor" tier trains on your inputs and is never used.
- **The demo is wearing the glasses.** The glasses camera streams to the phone; the phone lies face-up on the table showing the judge view. The iPhone-camera path exists only (a) so Devin can develop without hardware and (b) as the fallback if the glasses stream is not working by demo time.
- **Start right now:** Xcode 26.4 or newer (or Xcode 27) downloading on every Mac that will build the glasses code, Devin's included; Meta Developer Mode on the glasses and the two official sample apps streaming; ElevenLabs Starter plan ($1 first-month promo) and a Meta Model API key; Devin session S1.

## 2. What we are demonstrating (3 minutes, table-side)

1. Everyone in view is "person". Double-tap on the glasses (or volume-down, or "Familiar, who's here?") → "No one I know. Three people."
2. "Marcus" walks up: "Hi, I'm Marcus…" 20 seconds of chat. "Nice meeting you." → the glasses ask the wearer "Want to remember them?" (or the wearer presses the capture button / volume-up) → the phone speaker asks Marcus: **"Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?"** with the same question in large type and YES / NO on the phone screen → "Yes!" → glasses: "Saved. Marcus is in your contacts." The judge view's grey "person" box turns into a green "Marcus 0.71". The People screen shows the consent clip.
3. Marcus walks away and comes back from the right at about 2 m: "Marcus, coming from your right." … "Marcus, next to you." (Stretch: Marcus speaks first → "Marcus.")
4. A never-enrolled teammate walks up: the screen shows "person" and nothing is spoken about them. Roll call: "Marcus, ahead, close. One other person."
5. Tap Call in the People screen (stretch: "Familiar, call Marcus") → the dialer opens. Close on the banner *Known people only. Strangers are "a person". Faces never leave this phone.* and on Meta's own policy line: face identification is banned on these glasses except for approved accessibility apps; Familiar is built as that app, in Developer Mode, and Marcus can remove himself at any time.

Fixture clips (so Devin can test without a camera): `enroll_marcus`, `approach_marcus`, `leave_marcus`, `strangers`, `mixed`, `conversation` (with "Hi, I'm Marcus" and "nice meeting you"), `yes_reply`, plus `no_reply` and `distance_calibration`. Record them with the glasses' own video capture if possible; the shooting script is in `TEAM_CHECKLIST.md`.

## 3. Scope

**Must ship (MVP):** recognize consented people with position band and distance; appear / approach / arrive / leave cues; roll call on demand; remembering by spoken consent (name pulled from the conversation, consent clip kept, iOS contact created, tap-YES alternative); People screen with remove; Readiness screen; judge view; three triggers (glasses gestures if available, volume buttons, wake word); two audio routes; fixture-driven tests.

**Stretch, in order:** (1) "who is talking to me" — whisper the name the first time a known person speaks; (2) ElevenLabs conversational agent for free-form questions, on demand only, and only if the MVP is stable by about 8 AM; (3) wave and smile cues; (4) call/text by voice without the agent.

**Cut, on purpose:** NFC tag and web enrollment, notifications to known people, voice/speaker identification (the HFP mic is beamformed to the wearer and the policy risk equals faces), space awareness (doors/tables), mood reading, any server-side storage, clock numbers in cues (the camera sees 41–53° horizontally, so "11 o'clock" would almost never be literally true; we say ahead / left / right / far left / far right).

## 4. Decisions and why

| Topic | Decision | Why |
|---|---|---|
| Glasses SDK | Meta Wearables Device Access Toolkit (DAT) **1.0.1**, SPM `https://github.com/facebook/meta-wearables-dat-ios` tag `1.0.1`, products `MWDATCore`, `MWDATCamera`, `MWDATMockDevice` (+ `MWDATInputs`). Needs **Xcode 26.4+ / Swift 6.3+**, iOS 17.2+, Meta AI app ≥ V292, glasses firmware ≥ V128. Developer Mode needs no Developer Center account (`MetaAppID` "0") | Research |
| Glasses transport | **Bluetooth Classic** (Info.plist: `UIBackgroundModes` includes `external-accessory`; `UISupportedExternalAccessoryProtocols` = `com.meta.ar.wearable`). On Wi-Fi transport the glasses mute app audio during a stream (Meta maintainer, issue #358); on Classic the stream and A2DP audio share the link and Meta's BirdSpotter sample speaks over it | Cues must come from the glasses |
| Stream | `StreamConfiguration(videoCodec: .hvc1, resolution: .medium /* 504×896 */, frameRate: 24)`, software-decoded with VideoToolbox so it survives backgrounding; `.low` 360×640 if bandwidth forces it. Recognition range on the stream ≈ 1.5 m (face ≥ 50 px), so stage approaches from 2 m. First frame can take ~12 s; LED on by design | Research |
| Audio Route A (default) | **Phone mic + glasses speakers over A2DP.** `.playAndRecord`, mode `.default` (not `.voiceChat`, which implies HFP), options `[.allowBluetoothA2DP, .defaultToSpeaker]`, built-in mic preferred. **The HFP route must stay closed during a DAT session** (opening it ends the session, issue #342). Sentences addressed to the other person are forced to the **phone loudspeaker** | Open-ear speakers point at the wearer; HFP is narrowband and kills the stream |
| Audio Route B | Glasses HFP mic + speakers when no glasses stream is running: `.voiceChat` + `inputNode.setVoiceProcessingEnabled(true)` | Fallback tiers 3–4 |
| Optional glasses mic | In-stream PCM: `audioCodec: .pcm(sampleRate: .rate16000, numberOfChannels: 1)` → `stream.audioFramePublisher` (not beamformed, dev-only, ~200 ms behind video) | Try in S6 if the phone mic hears the other person badly |
| Glasses gestures | `MWDATInputs`: `.select` (double tap) = who's here, capture button `.shortPress` = remember them; single tap and hold are reserved by Meta | Research |
| Phone trigger | Volume buttons via `AVCaptureEventInteraction` (iOS 17.2+; needs a running `AVCaptureSession`) plus wake word "Familiar" fuzzy-matched in the on-device transcript plus on-screen buttons | Wake words misfire in noise; Picovoice's free tier ended June 2026 |
| Face embedding | **InsightFace `w600k_mbf.onnx`** (buffalo_sc pack, 13 MB, 512-d, 112×112 RGB, (x−127.5)/127.5, 5-point ArcFace alignment) via **ONNX Runtime SPM 1.24.2**, CPU first (10–20 ms), CoreML EP as an optimization. The Modal fallback runs the **identical model**, so galleries interchange and Modal doubles as the correctness oracle (same crop → cosine > 0.99). Start threshold 0.40 cosine, margin 0.08 over the runner-up, 3-vote identity lock. Non-commercial license: fine for the hackathon, noted in the README. Apache-2.0 alternative: OpenCV Zoo SFace (128-d, threshold ≈ 0.36) | Ready ONNX, zero conversion, one model everywhere |
| Face detection | Apple Vision `VNDetectFaceRectanglesRequest` revision 3 (roll/yaw/pitch) + `VNDetectFaceLandmarksRequest` revision 3 with `.constellation76Points` and `inputFaceObservations`. The `VN*` classes, not the new Swift `DetectFaceLandmarksRequest` (reported out-of-range landmarks on iOS 26) | Free, on the Neural Engine |
| Speech in | iOS 26 `SpeechAnalyzer` + `SpeechTranscriber` (preset `.timeIndexedProgressiveTranscription`) + `SpeechDetector` as VAD; `SFSpeechRecognizer` on-device fallback. Rolling 90 s in RAM. **SpeechAnalyzer does not run in the Simulator** → `FakeTranscriber` | Free, private |
| Speech out | ElevenLabs `eleven_flash_v2_5`, PCM 16 kHz, disk-cached and pre-warmed for the whole cue vocabulary; Apple voice after 1.2 s without a first byte; short earcon before cues. **Starter plan now** ($1 promo through Nov 1: 75k chars + 75 agent minutes; Free is 10k chars) | Voice quality; the cache makes cues instant |
| Text LLM | Regex first (instant). Then Apple Foundation Models and the Meta Model API **raced in the background during the conversation**, caching the best name guess per track so the consent question never waits on a model. `muse-spark-1.3`, `reasoning_effort` low/minimal, JSON-schema output, 1–3 s | User choice + latency reality |
| Enrollment trigger | Explicit command/button goes straight to gathering. Goodbye phrases ("nice meeting you", "see you") trigger the quiet "Want to remember them?" first | Saves a round trip on stage |
| Consent answer | Spoken yes (rules first; unclear → one re-ask) **or** a tap on a full-screen YES / NO card | Noisy room; accessibility story |
| Persistence | Codable JSON file store (`people.json`, `thumbs/*.jpg`, `consents/*.wav`) | Model changes hourly; no migrations |
| Contacts | `CNMutableContact` with name, phone, image, `jobTitle` "Met via Familiar · HackTX · Oct 25 2026", `organizationName` "Familiar". **Never `note`**: it needs an Apple-approved entitlement and the save fails without it | Research |
| Backend | None for the MVP. Modal only for the embedding fallback (CPU container; `min_containers=1` during judging only). Neon unused | Product over infrastructure |
| Toolchain | Deployment target iOS 18; iOS 26 APIs behind availability checks; Swift 5 language mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; synchronized folder groups so parallel sessions never touch `project.pbxproj` | Parallel Devin sessions |
| Policy | Developer Mode only. Meta's Acceptable Use Policy: *"Use device sensors for unique identification of people based on physical characteristics, such as voices and faces; exceptions are granted for specific use cases, including accessibility apps, with prior Meta approval."* No published exception process exists yet; the pitch names it. Everyone enrolled is a consenting teammate; data wiped after the demo | Research |

## 5. Architecture

```
 FrameSource ─frames─▶ Perception ─events─▶ CuePolicy (pure) ─▶ CueGate ─▶ Speaker ─▶ AudioEngineController
 (phone | glasses | video)  detect→track→align→embed→match→band/distance→trajectory                   (one owner of session, engine, tap,
 AudioInput ─16 kHz─▶ Transcriber (rolling 90 s, RAM) ─▶ WakeWord/CommandParser ─▶ CommandRouter          player, route recovery, gating,
             ├──▶ VAD (SpeechDetector) + loudness split (user/other) ─▶ ActiveSpeaker (stretch)             speaker override)
             └──▶ 30 s PCM ring buffer ─▶ ConsentClipWriter (WAV)
 ConsentFlow = Transcriber + NameExtractor cache + YesNoClassifier + Speaker + Perception + PeopleStore + ContactsBridge
 PeopleStore (JSON) ─▶ ContactsBridge (CNContact; tel: / sms:)     UI: Readiness · Home · People · Person · Settings · Judge view · Consent card
```

Clock rule: all timestamps are host-clock seconds. Streams: `subscribe() -> AsyncStream<T>` per subscriber. The full Swift contracts, repo layout, vocabulary and working rules are in `AGENTS.md`.

**Perception.** Vision detection on a ≤ 960 px downscale; alignment and 256×256 thumbnails from the full-resolution buffer; embeddings only for faces ≥ 50 px. Greedy IoU tracker (confirmed after 3 hits, lost after 2.5 s). Each track keeps its top-8 embeddings by quality × yaw diversity. Embedding cadence: every 0.5 s until identity locks, then every 3 s; unknown tracks every 1 s for 10 s, then every 5 s; `requestBurst` gives 4/s during enrollment. Match = cosine against every stored embedding (max per person), accept at ≥ T with margin ≥ 0.08, otherwise unknown. Bearing bands by fraction of frame width; distance bins from face height and vertical FOV, calibrated at 1 / 2 / 3 m; approaching = bin decreased or box height +25 % over 1.5 s; arrived = close and stable 1 s; left = confirmed track lost > 2.5 s.

**Audio and speech.** One `AudioEngineController` owns the session (activated once at launch, never deactivated, to avoid Bluetooth setup lag), the engine, the mic tap, the TTS player, route recovery (re-install the tap on `AVAudioEngineConfigurationChange`), and playback gating (samples fed to the transcriber are zeroed while the app speaks, +300 ms). A 30 s PCM ring buffer feeds the consent clip. A loudness split tags segments as `user` or `other` after a one-sentence calibration.

**Consent flow.** Trigger → `gathering` (pin the unknown track facing the user; burst embeddings; need 3 good ones) → `asking` (cached name only if confidence ≥ 0.7 and only from `other`-attributed speech; question pre-synthesized; phone speaker; consent card) → `listening` (≤ 6 s; yes rules; one re-ask) → `saving` (embeddings, thumbnail, WAV clip, meeting context, contact; label flips immediately) or `declined` ("Okay, nothing saved." and everything discarded).

**Cue policy.** Silence by default; ≥ 4 s between utterances; per-person cooldowns; nothing while the user is speaking or the consent flow is active; strangers never described beyond "someone close" in chatty mode; roll call on demand.

## 6. Schedule (CDT; kickoff ≈ 8 PM Sat)

| When | Who | What |
|---|---|---|
| 8:00–8:30 PM | Humans | Give Devin access to this repo; Xcode 26.4+/27 downloads; Meta Developer Mode + both sample apps; ElevenLabs Starter + key; Meta Model API key; Devpost team. `TEAM_CHECKLIST.md` |
| 8:00–9:30 PM | Devin **S1** `devin/01-skeleton.md` | Project, contracts, fixture and scripted sources, fakes, Home + Judge skeleton, pushed to `main`. Blocks everything else |
| 8:30–9:30 PM | Two humans | Record and commit the fixture clips and transcripts |
| 9:30 PM–3:30 AM | Devin **S2 ∥ S3 ∥ S4 ∥ S9 ∥ S6 (mock)** | Perception; audio/speech/voice; app, memory and consent; Modal twin; glasses source against the Mock Device Kit. Humans on call (sessions sleep after 30 idle minutes) |
| 3:30–7:00 AM | Devin **S5** + two humans on devices | Merge, wire, Readiness, HANDOFF, calibration at the real table on both audio routes |
| 7:00–9:30 AM | Humans + Devin **S6 hardware pass**, then **S7**, **S8** (gated) | Glasses stream and A2DP cues verified; who-is-talking; agent only if everything else is stable by 8 AM |
| 9:30–11:15 AM | Humans | Rehearse three times, record the demo video (= Devpost video), Devpost text, confirm no keys in git history, Devin disclosed, **submit by 11:15 AM** |
| 1:30 PM | Everyone | Charge, warm the caches and Modal, start the stream two minutes before judges arrive. Judging 2–5 PM |

Devin conventions: macOS platform per session; one verifiable sub-task per session (≤ 3 h); acceptance criteria and test output in the PR; secrets through Devin's secrets store; S2–S4 never edit `Core/*` or `project.pbxproj`.

## 7. Fallback tiers (selectable in Settings)
1. **Wearing the glasses:** glasses camera over Classic + glasses A2DP audio + phone mic.
2. Glasses camera over Wi-Fi + phone speaker for all audio.
3. Phone camera held or clipped at chest height, pointing forward + glasses audio (A2DP, or HFP Route B).
4. Phone camera + phone speaker.
5. Live perception on a fixture clip in the judge view + the recorded walkthrough.

## 8. Top risks and the mitigation built in
Marcus can't hear the question (open-ear speakers face the wearer) → phone loudspeaker + consent card. Glasses mute app audio on Wi-Fi → Classic transport. HFP kills the stream → Route A keeps HFP closed. Gen 2 firmware 129 Wi-Fi join failures (GitHub #354/#356) → Classic; fold/unfold; reboot the phone. Mic dies on a route change → engine recovery + mic meter on the judge view. Clipped first syllable → session always active + 150 ms leading silence. Short recognition range → stage from 2 m. Wake word misfires → gestures and volume buttons. The app transcribing its own voice → sample zeroing. Consent clip truncated → 30 s ring buffer. Permission storm / models not downloaded → Readiness screen before 7 AM. Wrong name in the question → only `other`-attributed speech, never the wearer's name. Meta API 1–3 s → background cache. Foundation Models throttled while the camera is open → raced with the Meta API. A judge labelled "Marcus" → threshold slider and live scores tuned in the room. Classic transport leaks ~4 MB/min → restart the app before each glasses session. Xcode below 26.4 → DAT won't build → download now.

## 9. Pitch notes (Meta track)
Lead with the moment, not the model: a blind person says hello first. Then the consent model as the product: nobody is recognized without saying yes, removal is instant, faces never leave the phone, the LED is always on, strangers are "a person". Then the Meta fit: built on the Wearables Device Access Toolkit in Developer Mode, Meta Model API for language, aimed squarely at the accessibility exception Meta's own policy carves out. Disclose Devin and the on-device models (InsightFace MobileFaceNet, Apple Vision, Apple Speech, Apple Foundation Models). Say what is cut and why.

## 10. Sources (verified Oct 24 2026)
Meta DAT: https://github.com/facebook/meta-wearables-dat-ios · changelog and samples (`samples/CameraAccess`, `samples/BirdSpotter`) in that repo · https://wearables.developer.meta.com/docs/develop/dat/getting-started-toolkit/ · https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/ · https://wearables.developer.meta.com/docs/develop/dat/mock-device-kit/ · https://wearables.developer.meta.com/docs/develop/dat/microphones-and-speakers/ · https://wearables.developer.meta.com/acceptable-use-policy · https://developers.meta.com/wearables/faq/ · docs MCP server https://mcp.developer.meta.com/wearables · GitHub issues/discussions #358 (audio muted during Wi-Fi stream), #342 (HFP ends session), #354/#356 (firmware 129), #324 (Classic memory growth), #331 (mock in Simulator), #313 (App Store).
Meta Model API: https://dev.meta.ai/docs/overview · https://dev.meta.ai/docs/models · https://dev.meta.ai/docs/pricing-rate-limits · https://dev.meta.ai/docs/structured-output · https://dev.meta.ai/docs/protocols/chat-completions · https://dev.meta.ai/docs/reasoning · https://dev.meta.ai/legal/terms-of-service · https://dev.meta.ai/help/about-model-api/llama-and-model-api
ElevenLabs: https://github.com/elevenlabs/elevenlabs-swift-sdk (v3.4.0) · https://elevenlabs.io/docs/api-reference/text-to-speech/convert · https://elevenlabs.io/docs/models · https://elevenlabs.io/pricing/api · https://elevenlabs.io/pricing/agents · https://elevenlabs.io/docs/agents-platform/libraries/swift · https://elevenlabs.io/docs/agents-platform/customization/tools/client-tools
Face recognition: https://github.com/deepinsight/insightface/tree/master/model_zoo (buffalo_sc) · https://github.com/microsoft/onnxruntime-swift-package-manager (1.24.2) · https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html · https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface
Apple: https://developer.apple.com/documentation/speech/speechanalyzer · https://developer.apple.com/documentation/speech/speechtranscriber · https://developer.apple.com/documentation/speech/speechdetector · https://developer.apple.com/documentation/foundationmodels · https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest · https://developer.apple.com/documentation/avkit/avcaptureeventinteraction · https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.contacts.notes
Infra and tooling: https://modal.com/pricing · https://modal.com/docs/reference/modal.fastapi_endpoint · https://docs.devin.ai/onboard-devin/environment/macos-support · https://docs.devin.ai/tutorial-library/ios-app · https://docs.devin.ai/essential-guidelines/instructing-devin-effectively
HackTX: https://hacktx.com/ · https://hacktx26.devpost.com/ · https://hacktx26.devpost.com/rules
Later work only: MediaPipe Face Landmarker (smile blendshapes) https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios · yolov8n-oiv7 (Door/Table/Countertop classes, AGPL) https://docs.ultralytics.com/datasets/detect/open-images-v7/ · Depth Anything V2 Small Core ML https://huggingface.co/apple/coreml-depth-anything-v2-small
