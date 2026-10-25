# Poyo, one voice — master plan (speed + one cohesive assistant)

Status of `main` at the time of this audit (Sun Oct 25, ~06:45 CDT): builds clean, 259 tests pass (9 skipped), 10 files
uncommitted (the "packed room" pass). Submission is 11:30 AM, judging 2–5 PM. The plan is tiered accordingly:
**Tier A** fits before submission, **Tier B** is judging-window polish, **Tier C** is the real architecture, after the hackathon.

Nothing here loosens the product rules in AGENTS.md: Poyo still never joins a conversation on its own, strangers stay
"someone", directions stay clock positions, every image is still redacted on the phone, consent is still the other
person's. "Human-like" comes from speed, continuity, memory, interruptibility and one consistent voice — not from chatter.

---

## 1. What it feels like today, and why

### 1.1 Seven speakers, one queue, no shared mind
Every spoken line comes from one of seven independent producers, each with its own policy, cooldown table, phrasing
register, earcon choice and priority, all funnelled into `VoiceSpeaker`'s priority queue (`minimumSpacing` 4 s, depth 2):

| Producer | File | Says things like | Knows what the others said? |
|---|---|---|---|
| People cues (`FamiliarCuePolicy`) | `Voice/CuePolicy.swift` → `App/AppCoordinator.handle(event:)` | "Marcus, 12 o'clock, close." / "Marcus left." / "Marcus." (−6 dB) | no |
| On-device scene (`SceneAwareness` + `HazardPolicy` + `ActionCaptioner`) | `Perception/SceneAwareness.swift` → `AppCoordinator.handle(scene:)` | "Stairs ahead." / "Kitchen." / "Someone crossing, left to right, close." | no |
| Vision reading (`NarrationPolicy`) | `Voice/NarrationPolicy.swift` → `AppCoordinator.handle(reading:)` | "Wall ahead, 3 meters." / "Stairs down, 12 o'clock, 3 meters." / gist | no |
| Commands (`CommandRouter`) | `Flows/CommandRouter.swift` | roll call, "Quiet mode.", "Calling Marcus.", on-device surroundings concatenation | no |
| Poyo answers (`PoyoBrain`) | `Voice/PoyoBrain.swift` | model sentence ≤ 15 words | only its own `lastAnswer` |
| Consent (`SpokenConsentFlow`) | `Flows/ConsentFlow.swift` | coaching + questions to the other person | no |
| Chime / self-enroll | `UI/FlowRuntime.swift`, `UI/SelfEnrollModel.swift` | earcon, card prompts | no |

49 call sites call `speaker.speak` directly. Consequences the wearer hears:

- **Duplicate hazards from two detectors.** On-device Vision says "Stairs ahead." (dedupe key `hazard:stairs`,
  `AppCoordinator.swift:232`) and the vision model says "Stairs down, 12 o'clock, 3 meters." (key `hazard:stairs down`,
  `NarrationPolicy.swift:109`). Different keys, different cooldown tables, both priority 0 with a chime → the same stairs
  announced twice, in two phrasings, seconds apart. That is literally "object detection and people detection as separate
  systems" made audible.
- **Register mismatch.** Cues are telegraphic templates ("Marcus, 12 o'clock, close."), command replies are
  concatenations ("Stairs ahead. Marcus, 12 o'clock, close. No one else. Kitchen. Table, chair." —
  `HazardPolicy.describe`), and Poyo's answers are full sentences ("A door at 1 o'clock, about 3 meters."). Three voices
  of style from one voice of audio.
- **The model does not know what the app just said.** `PoyoBrain.answer` gets `lastAnswer` (one line) + 30 s of raw
  transcript. The transcript never contains Poyo's own speech (the mic is gated while the app speaks), so after the
  app says "Marcus left." and the wearer asks "where did he go?", the model has no idea anything was said. Poyo also
  cannot answer "you just said a door — which side?" except within the one-line `lastAnswer`.
- **Earcons are inconsistent**: chime before people cues, before path alerts, before the roll call; none before Poyo
  answers; a different chime for "heard you". The ear learns "several machines", not one person.
- **Priority 0 cuts Poyo off mid-sentence.** A roll call, a mode confirmation and a path alert are all priority 0 and
  clear the queue (`VoiceSpeaker.speak`), so "Who's here?" or a wall alert interrupts an answer mid-word.

### 1.2 Where the time goes (end of the wearer's sentence → first word of the answer)
Measured from the code paths; latencies in brackets are the ones the team already logged.

| Stage | Today | Why |
|---|---|---|
| End of speech → wake hit | **1.0–1.3 s** (bare "Poyo." up to 4 s) | `WakeWord.settle = 1.0` s of unchanged volatile text, polled every 100 ms (`WakeWord.swift:13`, `CommandParser.swift:112`); `collectWindow` 4 s. The `SpeechDetector` end-of-speech verdict already exists (`SpeechAnalyzerTranscriber.swift:88`) but is only fed to the loudness split, never used to flush the wake word. |
| Wake hit → chime | ~0.2 s | `heardYou` earcon (fine) |
| Chime → model reply | **1.6–2.8 s** | `VisionLLMClient.complete` waits for the **whole strict-JSON** reply (`{say, action, name, mode}`); no SSE although the Meta Model API supports `stream: true`. Before the call, `scene.redactedSnapshot()` runs a fresh Vision face detection + redaction + JPEG **on the main actor** inside `PoyoBrain.answer` (`PoyoBrain.swift:153`): ~50–120 ms serial, plus a UI hitch. The first question also pays a TLS handshake: `warmUp()` warms `MetaModelClient`'s session, but `VisionLLMClient` has its own `URLSession` (`VisionLLMClient.swift:23`). |
| Reply → audio | **0.8–1.5 s** | `ElevenLabsTTS.fetch` waits for the **whole body** (`for try await byte in bytes { data.append(byte) }`, `ElevenLabsTTS.swift:83`) before `playback.play`; no streaming although the model is `eleven_v4_turbo` (~100 ms inference). Every answer is a cache miss. Then `leadingSilence` 150 ms. Bluetooth A2DP adds ~200 ms. |
| Boot-time saturation | +0.5–1 s for minutes | `prewarm` of ~80 alert phrases runs through the **same 2-slot semaphore** as live requests (`ElevenLabsTTS.swift:65`, `VoiceSpeaker.prewarm` concurrency 2) → a live answer queues behind prewarm on a cold cache. |
| **Total** | **≈ 4–6 s** | A person answers in < 1 s. |

People cues have their own lag: event → `leadingSilence` 150 ms → earcon 160 ms → **up to 4 s `minimumSpacing`** →
TTS. `Phrasebook.prewarmSet(names:)` exists (`VoiceContracts+.swift:108`) but is only called from Demo controls, never
at boot or after a save, so the first "Marcus, coming toward you." after enrolling Marcus pays a full ElevenLabs round
trip or falls to the Apple voice after 3 s — a voice switch in the middle of the demo.

### 1.3 Turn-taking is not a conversation
- **No barge-in.** `transcriberInput` is zeroed while the app speaks plus 300 ms (`AudioEngineController.swift:39`).
  The wearer cannot say "Poyo, stop" or interrupt an answer. `Command.cancel` exists but cannot be heard while speaking.
- **Follow-ups only after a question.** `noteAnswered()` opens the 8 s window only if Poyo's line ends with "?"
  (`PoyoBrain.swift:89`). After a plain answer the wearer must say "Poyo" again. `QuestionFilter.isRequestLike`
  (`SpeechSanitizer.swift:27`) was written for exactly this gating and is now dead code (only tests use it).
- **"Say that again" repeats the wrong thing** after a Poyo answer: `CommandRouter.repeatLast` re-speaks
  `lastUtterance`, which only `CommandRouter.say` sets (`CommandRouter.swift:194`); `PoyoBrain` speaks directly.
- **No memory of the wearer.** Nothing stores preferences ("say steps, not meters", "don't mention chairs"), what Poyo
  already told them, or people context beyond first names (`knownNames`). "Who's Marcus again?" has no answer even
  though `Person.met` holds when and where they met.
- **Speaker labels in the prompt are guesses.** The loudness split is uncalibrated by default (`userRMS 0.08`) and
  commit `975ab47` stopped trusting it, yet the prompt still labels lines "Wearer:" / "Other:" (`PoyoBrain.swift:156`).

### 1.4 Two brains drifting apart
`PoyoBrain` (default) follows rule 9; the alternative `AgentSession` still sends every wearer sentence as `[overheard]`
and may answer unsolicited at priority 1 (`AgentSession.swift:200-241`), uses a 12-word prompt, a different tool set
(no rename, no live view) and its own phrasing. Flipping Settings → Assistant changes Poyo's personality.

### 1.5 Smaller defects found on the way
- `SpeechSanitizer.personDetail` is a blunt word list: it drops any sentence containing "face" (the clock face), "happy"
  (Happy Hour sign), "guys", "kids", "hair" (hair salon) — legitimate sign readings get eaten.
- `RulesYesNo` in `App/Services.swift:217` matches substrings ("I know" → no, "not sure" → yes). Unused in the bridged
  path (the flow uses `RulesYesNoClassifier`), but exposed as `Services.yesNo` — a trap.
- `PoyoBrain.answer` calls `noteAnswered()` twice (`defer` + explicit).
- `AppCoordinator.conversationActive` = "speech in 12 s + a near facing face": a near stranger who is not talking to
  the wearer still mutes cues and the gist.
- Uncommitted work on `main` (10 files + `MotionStateTests.swift`). Tests pass with it; commit before anything else.

---

## 2. Target architecture: one Mind, two lanes, one Voice

```
Perception ──people events / tracks──┐
SceneAwareness ──hazards, place, actions──┤
CloudScene ──SceneReading──────────────┤      ┌──────────────── WorldModel (stateful) ────────────────┐
Transcriber ──speech, wake, endpoints──┼─────▶│ entities (people + things) with position, age, source │
MotionState ──walking──────────────────┤      │ HazardRegistry deduped across detectors               │
Consent / self-enroll ──state──────────┘      │ place history · people last seen · what Poyo has said │
                                              │ DialogueMemory (turns, 5 min) · PersonalMemory (JSON) │
                                              └───────────────────────┬───────────────────────────────┘
                                                                      ▼
                                   Attention (ONE policy: mode, muted, walking, face-to-face,
                                   addressed / follow-up window, consent, "already said")
                                        │                                        │
                              Fast lane: PhraseComposer                Slow lane: PoyoBrain
                              templated, Poyo's register,              streaming LLM, multi-turn messages,
                              merges simultaneous facts,               same WorldModel + DialogueMemory,
                              < 300 ms (cache-hit TTS)                 tools + watches, first word < 1.2 s
                                        └──────────────┬─────────────────────────┘
                                                       ▼
                                   Voice: one persona · streaming TTS over one WebSocket ·
                                   previous_text continuity · sentence-boundary yielding ·
                                   hard interrupt only for safety · chime only for safety
```

Principles:
1. **Everything Poyo says is a turn.** The fast lane and the slow lane both write to `DialogueMemory`; the model sees
   what the app said ("Marcus left." is in its history), so "where did he go?" resolves.
2. **One hazard is one hazard.** On-device and vision detections of the same thing (kind + bearing bucket, within ~2 s)
   merge into one entity; the richer phrasing wins; one utterance, one cooldown.
3. **One register.** Cues, command replies and answers are composed from the same sentence patterns in Poyo's voice;
   the LLM prompt carries those patterns as style examples so the two lanes sound like one speaker.
4. **One interruption model.** Only safety (path/hazard alerts) hard-interrupts. Everything else yields at a sentence
   boundary. People cues and answers never cut each other mid-word.
5. **Speed first, then words.** Acknowledge in < 300 ms (chime), first spoken word in ≤ 1.2 s, filler at 700 ms if the
   model is slow, stream the rest.

---

## 3. Tier A — before submission (ordered; each step is independently shippable and testable)

| # | Change | Where | Est. | Why it matters |
|---|---|---|---|---|
| A1 | **Commit the working tree** on `main` (or `feat/packed-room`). | — | 5 min | Nothing else is safe until this is done. |
| A2 | **Prewarm the people vocabulary**: call `speaker.prewarm(Phrasebook.prewarmSet(names:))` at boot and again after every `ConsentState.done` / self-enroll save / rename. Give live requests priority: a second `AsyncSemaphore` (count 1) for `warm`, or pause prewarm while any live `synthesize` is pending. | `AppCoordinator.restart`, `FlowRuntime` (store.changes()), `ElevenLabsTTS` | 30 min | Removes the Apple-voice switch on the first cue for a new person; removes boot-time queueing behind ~80 prewarm calls. |
| A3 | **HazardRegistry (cross-detector dedupe)**: one struct in `AppCoordinator` keyed by `kind + clock bucket`; `handle(scene: .hazard)` and `NarrationPolicy` hazards/path alerts go through it; a match within 2.5 s is dropped unless it adds distance (then upgrade only if not yet spoken). Single cooldown table. | new `Voice/HazardRegistry.swift`, `AppCoordinator.handle(scene:)`, `handle(reading:)` | 40 min | Ends the double "Stairs ahead." / "Stairs down, 12 o'clock, 3 meters." |
| A4 | **DialogueMemory + model knows what was said**: new `Voice/DialogueMemory.swift` (ring of turns `{role: wearer/poyo/app, text, t}`, 5 min, ≤ 12 turns). Hook `VoiceSpeaker.onSpoken` (already exists) to record every spoken line as a Poyo turn; record `[to you]` questions as wearer turns. In `PoyoBrain.answer` send the last 8 turns as proper `messages` (user/assistant alternation) instead of the `You last said:` line. | `VoiceSpeaker.onSpoken`, `PoyoBrain.answer`, `VisionLLMClient` (accept a `history: [(role, text)]`) | 45 min | The single biggest "it understands me" fix. References resolve; Poyo stops repeating what the fast lane said. |
| A5 | **Follow-up window after every addressed answer** (6 s), not only after a question. Gate: `QuestionFilter.isRequestLike(text)` OR a discourse opener ("and", "what about", "how about", "ok", "thanks", "which"), AND `ActiveSpeaker` reports no visible mouth moving toward the wearer (so a stranger's sentence is not taken). Still rule-9 compliant: the window only opens because Poyo was addressed. | `PoyoBrain.noteAnswered`, `hear` | 25 min | Natural back-and-forth without "Poyo" every turn. |
| A6 | **Fix `repeatLast`**: `PoyoBrain` publishes its spoken utterance to `CommandRouter.lastUtterance` (or read it from `DialogueMemory`). Delete `RulesYesNo` in `Services.swift` (use `RulesYesNoClassifier`). Remove the duplicate `noteAnswered()`. | `CommandRouter`, `PoyoBrain`, `Services` | 15 min | Correctness; "say that again" works after an answer. |
| A7 | **Warm the right session and get redaction off the main actor**: share one `URLSession` between `MetaModelClient` and `VisionLLMClient` (or warm the vision client with a tiny text-only call at boot). Keep the last redacted JPEG in `CloudScene` (it already redacts every upload) and reuse it when < 1 s old; otherwise redact on a utility task. | `Services.make`, `CloudScene.redactedSnapshot`, `PoyoBrain.answer` | 25 min | ~150–400 ms off the first answer, no UI hitch per question. |
| A8 | **Faster endpointing**: feed `SpeechDetector`'s "speech ended" into `WakeWord` to flush pending volatile text immediately; drop `settle` 1.0 → 0.5 s as a fallback; `collectWindow` 4 → 3 s. Add `onEndpoint` to `SpeechAnalyzerTranscriber` (new type in `Speech/SpeechContracts+.swift`). | `SpeechAnalyzerTranscriber`, `WakeWord`, `WakeWordCommandSource.attach` | 30 min (device test) | ~0.6–0.8 s sooner chime and question. |
| A9 | **Streaming TTS (REST `/stream`) + chunked playback**: `ElevenLabsTTS.stream(text) -> AsyncThrowingStream<[Float]>` reading the body in chunks (not bytes); `AudioEngineController` gains `playStream(_:)` that schedules successive `AVAudioPCMBuffer`s on the player node and returns when the last one finishes; `VoiceSpeaker.perform` uses it for uncached text. Keep REST-full + Apple as fallback behind a Settings toggle. | `ElevenLabsTTS`, `AudioEngineController`, `VoiceContracts+` (new `StreamingPCMPlayback`), `VoiceSpeaker` | 60–90 min | Audio starts ~150–300 ms after the model finishes instead of after the whole clip is synthesized: −0.6 to −1.2 s per answer. |
| A10 | **Voice continuity & pacing**: pass the real previous spoken line as `previous_text`; `minimumSpacing` 4 → 1.5 s; `earcon: true` only for `hazard`/safety categories (people cues and answers get none; keep `heardYou`); `leadingSilence` 150 ms only when the output route is Bluetooth. | `ElevenLabsTTS.previousText` (set by `VoiceSpeaker` after each line), `VoiceSpeaker`, `CuePolicy`, `RollCall` | 20 min | One voice, one sound signature, cues arrive seconds sooner. |

Do A1–A7 first (≈ 3 h with device checks). A8–A10 if time remains; each is behind a flag or trivially revertable.

**Status (Sun Oct 25, ~08:00 CDT): A1–A10 landed on `main`** (commits `9e4f6e7`, `95455b7`, `53af8a2`; 277 Simulator tests
pass, 9 skipped). Decisions taken on the way, to verify on the iPhone:
- A3: no "upgrade" of an alert already admitted. Priority-0 alerts play within ~200 ms (cache hit), so replacing
  "Stairs ahead." with the model's richer line would cut it off mid-word. The richer line is dropped within 2.5 s;
  after that it plays only when it is news (closer by 1 m, newly close, 2 m farther, or the first distance for a
  thing announced without one when it is close). `HazardRegistry` keys path alerts as `obstacle@clock`, so the
  looming detector's "Obstacle ahead." and the model's "Wall ahead, 2 meters." are the same thing.
- A4: `DialogueMemory` records every spoken line with audience `.user` (consent lines to the other person are
  not turns). The brain records its own answer and the speaker hook records it again; same text within 10 s is one
  turn. Pronouns ("where did he go") no longer parse as `whereIs`, so they reach the model with the history.
- A5: the gate is `QuestionFilter.isRequestLike` or an opener (and / ok / okay / also / which / what about / how
  about / thanks), and no near, facing face with `mouthOpenness ≥ 0.06` (plus `ActiveSpeaker.otherIsSpeaking`).
  One sentence per window; a sentence that does not qualify closes it (the wearer is talking to someone).
- A9: streaming is **on by default** (`streamingTTS`, Settings → Voice). 300 ms jitter buffer before the first
  buffer is scheduled; a stream that never starts goes straight to the Apple voice without a second ElevenLabs
  try. `AudioEngineController.playStream` is untested in the Simulator (no audio device): if speech stutters on
  the phone, flip the toggle; the plain path is unchanged.
- A10: the chime stays on hazards, "heard you", the close-crossing collision cue, the consent question to the
  other person and "Someone is introducing themselves."; "Saved." lost it.

Acceptance before submission (Judge view + `poyo-log.txt`):
- No "TTS fell back to the Apple voice" lines in a 5-minute session.
- One hazard utterance per stairs/wall episode, never two phrasings.
- After "Poyo, what's around me?", "which side is the door?" (no wake word) is answered.
- "Say that again" repeats Poyo's last answer.

---

## 4. Tier B — judging window (low risk, visible in the demo)

| # | Change | Where |
|---|---|---|
| B1 | **Persona pass** on `PoyoBrain.systemPrompt`: one short persona block (warm, plain, first person, "I can't see that from here" instead of "unable to determine", hedges when `confidence` is low), the fast-lane sentence patterns as style examples, allow a longer answer (≤ 30 words) only when the wearer asks for detail ("tell me more", "describe"). Add `confidence` to the reply schema; below 0.5 the composer prefixes "I think". | `PoyoBrain` |
| B2 | **Thinking filler**: if no first token by 700 ms after the chime, play one of 4 prewarmed fillers in the same voice ("Mm, let me look.", "One sec.", "Looking.", "Hm."), round-robin; only for addressed questions, never for cues. | `PoyoBrain.answer`, prewarm list |
| B3 | **Register alignment for fast-lane cues** (Core owner): keep the data, add the verb — "Marcus is at 1 o'clock, close." / "Marcus is coming toward you." / "Marcus just left." / roll call "Marcus is straight ahead, close; one other person." Update `fixtures.json` and the Phrasebook tests together. | `Core/Phrasebook.swift`, `RollCall`, tests |
| B4 | **Judge view latency breakdown**: wake → endpoint → first token → first audio byte → audio start, per answer (`PoyoTrace`), plus the DialogueMemory tail. | `JudgeView.PoyoPanel`, `PoyoBrain` |
| B5 | **Demo script lines** that show the difference: interrupt-free follow-up ("which side?"), "say that again", one stairs alert, "Poyo, what did you just say about Marcus?" | `docs/DEMO_SCRIPT.md` |

---

## 5. Tier C — the real architecture (after the hackathon)

### C1. Streaming model with a speakable-first wire format
- `VisionLLM.stream(...) -> AsyncThrowingStream<String>` over SSE (`stream: true`, `Accept: text/event-stream`).
- Replace strict JSON with: **line 1 = the spoken sentence(s)**; optional **last line** `⟂{"action":"call","name":"Marcus","confidence":0.8}`.
  A sentence splitter hands each clause to the TTS stream as it arrives; the control line is parsed when the stream ends.
  Fall back to today's JSON call on parse failure. Target: first token ≈ 0.7–1.0 s with `reasoning_effort: minimal`.
- Consider the Meta **Responses API** for multi-turn continuity (the chat endpoint does not carry reasoning across turns).

### C2. One TTS WebSocket for the session (ElevenLabs multi-context `stream-input`)
- Open once at boot with `xi-api-key`, keep alive; each utterance is a context; text chunks are sent as the model streams;
  `flush` at sentence end; **closing a context stops audio instantly** → barge-in in < 100 ms, no per-line handshake.
- Audio tags (v4 turbo) only for a soft register on whispered cues; never for alerts.

### C3. Barge-in / echo-aware listening
- When the output route is A2DP (glasses) the phone mic hears almost no bleed: disable the mic gate and run the wake
  word on `rawInput`. On the loudspeaker, enable `setVoiceProcessingEnabled(true)` (AEC) instead of zeroing samples.
- A wake hit or "stop" during playback → stop the current context, no apology, chime. Humans just stop.

### C4. Stateful `WorldModel`
- Entities (people + things) with id, kind, bearing, distance, first/last seen, source (device/vision), and `saidAt`.
- Ring of the last 10 `SceneReading`s → `changes(since:)` for "what changed?" / "where did the door go?".
- People context for the brain: name, met when/where (`Person.met`), last seen bearing (`CommandRouter.lastSeen`), phone present.
- Replace `conversationActive`'s "any near facing face" with "a near face whose mouth is moving toward the wearer"
  (`ActiveSpeaker` data; not voice ID — allowed).

### C5. `PhraseComposer` (fast lane) and the `Attention` policy
- One place decides speak / hold / drop for every candidate fact, using mode, muted, walking, face-to-face, addressed,
  consent, and "already said within N s" from `DialogueMemory`.
- Merges simultaneous facts into one line ≤ 14 words: "Marcus is coming toward you; chair just ahead."
- Sentence-boundary yielding: non-safety priority-0 items wait for the current sentence to end; only safety cuts in.
- Retire the per-policy cooldown tables in `CuePolicy`, `NarrationPolicy`, `HazardPolicy`, `ActionCaption.utterance`
  into one table.

### C6. Memory that makes it "understand you"
- `PersonalMemory` (JSON in Documents, listed and clearable in Settings): preferences and facts stated **to Poyo**
  ("say steps", "don't mention furniture", "I'm looking for the registration desk"), written through a
  `remember_preference` action, never from overheard speech. Injected into the system prompt.
- `Watches`: "tell me when Marcus is back" / "tell me when we reach the stairs" → a small matcher over perception and
  scene events; speaks once when satisfied. Rule-9 compliant because the wearer asked.

### C7. One brain
- Delete `AgentSession`/`AgentToolRouter` or reduce it to the same prompt, tools and rule-9 behaviour (no `[overheard]`).
- Replace `SpeechSanitizer`'s word list with a model-side flag (`mentionsPeople: bool`) plus a narrow regex for the hard
  rules (no "Poyo", no SKIP, no redaction talk).

### C8. Attribution without voice ID
- Attribute "other" speech to the visible person whose mouth is moving (`ActiveSpeaker`); label the rest "you or someone
  off-camera". Drop the RMS split from the prompt labels.

---

## 6. Targets and how to measure

| Metric | Today | Tier A | Tier C |
|---|---|---|---|
| End of wearer's sentence → chime | 1.0–1.3 s | ≤ 0.5 s | ≤ 0.4 s |
| Chime → first spoken word (answer) | 2.8–4.7 s | ≤ 2.0 s | ≤ 1.2 s |
| People cue: event → audio start | 0.3–4.3 s (+1–3 s on a cache miss) | ≤ 0.5 s | ≤ 0.3 s |
| Same hazard spoken twice | common | never | never |
| Apple-voice fallbacks per 5 min | several on a cold cache | 0 | 0 |
| Follow-up without wake word | only after a "?" | after every answer, 6 s | plus barge-in |
| Model knows the last 8 things said | no | yes | yes + world history |

Instrument with `PoyoTrace` (B4) and the existing `DiagnosticLog`; every utterance already logs `said[p… category]`.

---

## 7. Risks and guards
- **Streaming with an image**: verify `stream: true` + `image_url` on `muse-spark-1.3` on the device before relying on it; keep the JSON path as fallback (C1).
- **TTS WebSocket quotas**: one connection per session, contexts closed promptly; REST `/stream` (A9) is the fallback.
- **Barge-in on the loudspeaker**: AEC changes the input format and adds latency; test with `AudioEngineController.installTap` (it already handles format changes). Default to A2DP behaviour.
- **Register change (B3) touches `Core/Phrasebook.swift` and fixtures**: do it with the Core owner, update tests in the same commit.
- **Follow-up window in a crowd**: the gate (request-like + no mouth moving toward the wearer) is what keeps rule 9; log every accepted follow-up so the device log shows why.
