## Cool things in our application

**You get to say hello first.** A friend who agreed to be remembered walks up, and the glasses say "Maya, approaching from your right." before she speaks. That one moment is the whole product: not recognizing a face, but handing someone the chance to start the conversation.

**Consent is the architecture, not a checkbox.** Nobody can be added silently. The other person's spoken "yes" (attributed to them by voice loudness) or their own tap on a YES/NO card is the only thing that saves anything, and we keep a few-second clip of the question and the answer as the receipt. Remove deletes the face data, the photo, the clip and the iOS contact the app created.

**Faces never leave the phone.** Recognition is fully on-device: Apple Vision finds and tracks faces, five landmarks align each one to 112×112, and InsightFace's MobileFaceNet (through ONNX Runtime) turns it into a 512-number vector. A name is spoken only after a 0.40 cosine match, a 0.08 lead over the next person and three agreeing votes in a row. When unsure, it says "someone", because a wrong name is worse than none.

**Black boxes before anything goes to the cloud.** The scene reader sends Meta's `muse-spark-1.3` a 512 px frame with every face blacked out first (a fresh face detection plus every tracked box, grown by 35 %). If face detection can't run, nothing is uploaded. The model is told never to describe people, and a sanitizer drops any sentence about looks, clothes or mood before it is spoken.

**Spatial cues from real geometry.** Direction comes from the face's position across the glasses' 53° field of view, turned into a clock hour; distance from a pinhole estimate of face size (close under 1.5 m, medium to 3 m, far beyond). "Approaching" means the face box grew 25 % within 1.5 s; "left" means unseen for 2.5 s.

**It knows who is talking to you.** While the microphone hears someone other than the wearer, the app finds the known face whose lips move the most and whispers that name once, 6 dB quieter. Strangers are never candidates.

**It knows when to stay quiet.** Routine lines wait for a pause in the conversation; hazard alerts only play while you're walking (phone motion above 0.15 g); each hazard kind is said at most once a minute; a registry keyed by hazard and clock position stops two detectors from announcing the same stairs twice; a person seen in the last 8 s is not announced again.

**Two hazard detectors, one voice.** On the phone and offline: Vision image classification catches stairs, escalators and crosswalks (0.5 confidence in 2 of the last 3 passes), and optical flow in the centre of the view says "Obstacle ahead" when time to contact drops under 1.8 s. In the cloud: the face-redacted scene reading reports the walking path, hazards, the place and signs. An obstacle within 4 m interrupts anything else, with its distance aged by 0.7 m/s so stale readings don't cry wolf.

**Poyo, an assistant that never butts in.** It answers to its wake word, a volume-button push-to-talk, or a follow-up within 6 s of its last answer, and even then it stays silent if someone in view is visibly talking to you. Built-in commands (who's here, remember them, call, text, where is, quiet/normal/chatty, say that again) are parsed on the phone with regular expressions and never leave it. Anything else is one vision-model call (1.6 to 2.8 s measured) that returns `{say, action, name, mode}`; actions go through the same command router as the buttons, so the model can never decide consent.

**A voice that starts in 300 ms.** ElevenLabs `eleven_v4_turbo` streams 16 kHz PCM and playback begins after 300 ms of buffer; every line is cached on disk, and alerts and every saved name are synthesized ahead of time. If nothing arrives within 3 s, Apple's on-device voice says the line instead. One priority queue: safety and consent interrupt, everything else waits its turn.

**The glasses stay a headset without killing the camera.** The camera streams HEVC at 24 fps over Bluetooth Classic, which keeps going with the phone locked. Audio goes phone-mic-in, glasses-speakers-out, because opening the glasses' headset microphone would end the stream. Double tap on the frame is "who's here?", the capture button is "remember them".

**Designed for the whole spectrum of vision.** One preference (Balanced, Low vision, Severe, Non-visual) scales every font, icon, weight, contrast and tap target. Every control has a VoiceOver label and hint, the room radar reads as a single sentence, every spoken line also appears as text for 5 s with a Repeat button, and speech rate and volume are the wearer's to set. Mimo, the little light-being, is drawn with libraries.dev's native avatar kit and is purely decorative, so screen-reader users lose nothing.

**Quick facts with a privacy rule.** "Poyo, look up the Longhorns score" sends only the query text to a search API, and any query containing a saved person's name or the wearer's name is refused: "I don't look people up."

**Works offline.** Recognition, on-device hazards, every built-in command and the Apple voice keep working with no network at all.

**Built to be tested without the hardware.** 308 test functions across 43 files; recorded clips stand in for the camera, a scripted perception file for recognition, transcripts replay line by line, and a mock glasses device plays HEVC into the real pipeline.

### What leaves the phone

| Service | What is sent | When |
| --- | --- | --- |
| Meta Model API (`muse-spark-1.3`) | 512 px JPEG with every face blacked out, plus text context | Scene readings and Poyo questions |
| Meta Model API | Text snippets of the transcript, a reply to classify | Name extraction, yes/no when on-device rules are unsure |
| ElevenLabs TTS | The text to speak | Each line not already cached |
| ElevenLabs Scribe | A few seconds of audio | Only when Poyo is taking a new name for a rename |
| SerpApi | The search query text | Only on "look up…" requests |

Face vectors, photos, consent clips, contacts and the transcript stay on the phone. Strangers appear in uploaded images only with their faces blacked out, and in text only as a number.
