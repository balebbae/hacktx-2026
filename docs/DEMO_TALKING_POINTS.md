# Demo talking points

Everything we built, what we used, and why. Split by who presents it. Each feature says where it lives: `main`, a branch that isn't merged yet, or a standalone sample.

## Caleb: architecture and pipelines

The big picture (on `main`)

- One SwiftUI app on the iPhone, no backend. The Ray-Ban Meta Gen 2 glasses are only camera, mic and speaker. Why: the phone has the compute, and nothing personal needs a server.
- Glasses video comes in through the Meta Wearables DAT SDK. The phone camera and recorded fixture videos plug into the same `FrameSource` interface, so the whole app runs in the Simulator with no hardware.
- Every module talks through `AsyncStream` subscriptions and shared contracts in `Familiar/Core/Contracts.swift`. Why: nine people built modules in parallel without stepping on each other.
- Start with [the one-page overview](diagrams/overview.png). Then see [architecture](diagrams/architecture.png), [pipeline](diagrams/pipeline.png), [Poyo](diagrams/poyo.png) and [consent](diagrams/consent.png).

Recognizing people (on `main`)

- Apple Vision finds faces, a tracker keeps a stable id per person, faces are aligned to 112×112 and embedded with InsightFace `w600k_mbf` running in ONNX Runtime on the phone. Why: fast, offline, and faces never leave the device.
- The matcher only says a name when the score clears 0.40 and beats the runner-up by 0.08. Otherwise it's "someone". Why: a wrong name is worse than no name.
- Spatial turns the face box into a clock position and distance band ("Marcus, 12 o'clock, close."). Trajectory adds walking up and leaving.
- Optional Modal GPU embedding fallback for when the on-device model can't run. It gets aligned face crops and discards them.

Seeing the scene and hazards (on `main`)

- On device, `SceneAwareness` uses Vision plus "the view is steadily getting bigger" to catch walls, stairs and obstacles. `MotionState` uses phone motion so path alerts only play while you're walking.
- `CloudScene` sends a frame to the Meta Model API (`muse-spark-1.3`) when the scene changes or when Poyo is asked something. Why: a vision model can answer open questions like "which side is the door?".
- Before any image leaves the phone, `FrameRedactor` blacks out every face with a 35% margin. If face detection can't run, nothing is uploaded.
- The model also gets a short text line of what the phone already knows (names of people who agreed, a count of everyone else, recent hazards). Names never come from the cloud.
- `ActionCaptioner` adds short captions like two people talking side by side, never clothing or mood.

Poyo, one voice (on `main`)

- Wake word "Poyo", or press the volume button and just talk (push-to-talk). Why: a hackathon floor is loud and the wake word can get lost.
- A request that gets cut off waits for the rest, and a better final transcript corrects it. Cues wait for a pause so they never talk over "Poyo, …".
- Fixed commands go to `CommandRouter`: who's here, describe, call, text, where is, mute, quiet/normal/chatty mode, say that again. Anything else goes to `PoyoBrain` and the vision model.
- One `VoiceSpeaker` priority queue for everything. Hazards are priority 0 and interrupt. Why: one voice in your ear, never two things at once.
- `HazardRegistry` is shared by the on-device detector and the vision model, so the same stairs are only announced once, and again only when you're closer.
- `DialogueMemory` keeps the last 8 spoken turns in RAM and sends them as chat history. That's why follow-ups and "say that again" work.
- ElevenLabs TTS is streamed in 200 ms chunks so the first word comes fast. Names and alert phrases are prewarmed. Apple's on-device voice takes over if ElevenLabs can't start.
- Face-to-face mode: when someone is talking to you, Familiar stays quiet except for a friend arriving or a close hazard.

Consent and privacy (on `main`)

- Only the other person can say yes, out loud or by tapping YES. The wearer can't add anyone, and the LLM never decides consent.
- After a longer conversation with someone new, Poyo quietly suggests asking them. Then it scans their face, picks their name out of the conversation (ElevenLabs Scribe for those few seconds, then a name extractor), and listens for their yes.
- They can type their number on the phone, and it becomes an iOS contact. "Poyo, change their contact to Anish" renames them.
- They can also enroll themselves with "Introduce yourself" or the `familiar://introduce` link.
- Faces, embeddings and consent clips stay on the phone. Removing someone deletes everything, including the contact.

## Sahas: frontend and accessibility

The redesign is on the `sahas` and `devin/1761388600-ui-remodel` branches, not on `main` yet. `main` has the simpler Home, People, Settings, Judge view and consent card.

Design system

- Four vision profiles: balanced, low vision, severe, non-visual. Each one changes text size, icon size, font weight, tap target size (52 to 72 pt), contrast and motion. Why: low vision isn't one setting.
- Plus Jakarta Sans, Dynamic Type everywhere, high-contrast surfaces, no color-only state, and reduced motion when the profile or iOS asks for it.
- Mimo, the app's avatar, shows what Familiar is doing and is readable by VoiceOver.

Screens

- Today, Room, People and You tabs, plus onboarding.
- Room is a half-disc radar: you at the bottom, friends as labeled dots, strangers as plain hollow dots with no label. VoiceOver reads it as the same sentence Poyo would say.
- People has search and a map of where you met people. Person detail shows the consent record and a delete button.
- Judge view with face boxes colored by confidence and captions of what the wearer is hearing.

Voice control and tap-to-hear

- Everything important can be done by voice: who's here, describe, call, text, remember them, mute, change mode, say that again.
- The volume button is a menu with four choices: ask Poyo (push-to-talk), remember them, pause cues, who's here. Why: a physical button you can find without looking.
- Every spoken cue also shows as a toast with a Repeat button that says the line again through the same voice.
- Onboarding and the You tab have "hear a sample" buttons that play the real voice, or a VoiceOver announcement if the voice isn't ready, so VoiceOver users hear it once, not twice.
- VoiceOver labels and hints on every control, custom actions on cues, and a summary label for the radar.
- `FamiliarHaptics`: a small vocabulary of haptics (listening, accepted, someone you know, someone left, they said yes, paused, error) so you can feel what happened without the screen.
- Settings for speech rate, speech volume, haptics, keeping cue text on screen, and showing Mimo.

## Keane: APIs

SerpApi quick facts (branch `feat/quick-facts`, not merged)

- "Poyo, look up HackTX" or "what does that mean?" does one web search and says one short fact back.
- `SerpApiClient` calls `GET https://serpapi.com/search.json` with SafeSearch on and a 6 second timeout, in its own ephemeral URL session.
- It picks the best answer from Google's answer box, weather, sports, knowledge graph, or the top result, and trims it to something you can say out loud.
- An outright "look up" skips the vision model. Poyo's model can also ask for a lookup when a question needs one.
- It only sends the words you asked about. No camera frames, transcript, location or names.
- Plugged in behind a small `QuickFactSource` protocol, so Poyo and the agent tools can use it and tests can swap in a fake.
- The key is `SERPAPI_KEY` in `Secrets.xcconfig`, never committed. If there's no key, Poyo says "Search isn't set up."
- Why SerpApi: real search results through one simple JSON API, without scraping Google ourselves.

Instagram contact card (branch `keane`, `samples/muse`, standalone Python)

- Give it a public Instagram handle and it returns a short spoken contact card: who they are and what they post about.
- Uses Apify's Instagram profile scraper (`apify~instagram-profile-scraper`) for the public bio, captions and alt text, then Muse Spark (`muse-spark-1.3`) to write the summary.
- This is a third-party scraper, not Meta's official Instagram API. No login, no cookies, no following, no emails or phone numbers, no comments, no downloading images.
- Results are cached locally, with `--refresh` for a new lookup and `--scrape-only` to skip the model. Tests use mocked providers so they don't cost money.
- Keys are `APIFY_API_TOKEN` and `META_API_KEY` in a git-ignored `.env`.

Muse image (branch `keane`, `samples/muse`, standalone)

- Turn something you describe into an image with `muse-image-1.0` via `https://api.meta.ai/v1/images/generations`. Python and a Swift reference client.
- Only on an explicit request, never auto-posted or sent, and it never guesses what you're thinking.

General API points

- Keys live in config files or env vars, never in code or git.
- Send the least data possible: redacted frames for vision, a few seconds of audio for names, only the search words for SerpApi.
- Every cloud call has a timeout and an on-device fallback, so the app still talks when the Wi-Fi at the venue doesn't.
- Each API sits behind a small Swift protocol, so the Simulator and tests use fakes.
- APIs we used: Meta Model API (vision and chat), Meta Wearables DAT (glasses), ElevenLabs (streamed TTS, Scribe, text-only agent), Modal (optional embeddings), SerpApi (quick facts), Apify and Muse (samples).
