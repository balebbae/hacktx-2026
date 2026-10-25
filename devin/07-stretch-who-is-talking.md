# Devin session S7 (stretch) — Who is talking to me (branch `feat/speaking`; starts after S5 is on `main`)

Read `AGENTS.md`. You own `Familiar/Perception/ActiveSpeaker.swift` and small, clearly marked edits in `PerceptionPipeline` and `CuePolicy`. Time budget: 2 hours.

## Goal
When a **known** person speaks to the wearer for the first time in a conversation, whisper their name: "Marcus."

## Design
Inputs: `VoiceActivity` (`isSpeech` with `guess == .other`) and each known track's `mouthOpenness` series (inner-lip gap ÷ face height, already kept by `FaceTracker`). While speech is active and attributed to `other`: for each known, facing track compute the variance of mouth openness over the last 1.0 s; the track with the highest variance above 0.004 (tune on fixtures) sustained for ≥ 0.6 s is the speaker; emit `PerceptionEvent.speakingStarted(snapshot)` once per track-session (reset after the track has been lost for 5 minutes). Never emit for unknown tracks: strangers are not described. `CuePolicy`: `speakingStarted` → `Utterance(text: Phrasebook.speaking(name), priority: 1, category: "speaking", earcon: false)` played quieter (−6 dB); if `Utterance` cannot carry a volume, add a `SpeakerVolumeHint` type in `Voice/VoiceContracts+.swift` keyed by `dedupeKey`. Normal and chatty modes only.

## Tests
Synthetic series: two tracks, one with an oscillating mouth → only that one triggers; no trigger when the VAD says `.user`; exactly one event per track-session.

## Definition of done for a human
Marcus (enrolled) says "hey Priya" while facing the wearer → the glasses whisper "Marcus." once; a stranger talking produces nothing.
