# Familiar — human checklist (CDT; kickoff ≈ 8 PM Sat Oct 24)

Hard stops: **Devpost submission 11:30 AM Sun** · judging 2–5 PM Welch Hall · pitching 5:30 PM Welch 2.224. Everything Devin cannot do is here.

## Right now (8:00–8:30 PM) — unblockers
- [ ] Give Devin access to `github.com/balebbae/hacktx-2026` (AGENTS.md is already on `main`). Start **Devin S1** on a macOS machine with `devin/01-skeleton.md`; tell it the repo URL.
- [ ] Every Mac that will build the glasses code (and Devin's): **Xcode 26.4 or newer, or Xcode 27**. Check with `xcodebuild -version`. Downloads take an hour; start them now.
- [ ] Meta AI app ≥ V292 and glasses firmware ≥ V128 (Meta AI → Devices → gear → General → About). **Developer Mode:** Meta AI → Settings → App Info → tap the version number 5× → Developer Mode on. Only one third-party app can be registered at a time; Developer Mode switches itself off after firmware updates.
- [ ] Clone `https://github.com/facebook/meta-wearables-dat-ios` and run two samples on the demo iPhone: `samples/BirdSpotter` (Bluetooth Classic) and `samples/CameraAccess` (Wi-Fi). Write down: which transport streams, fps, seconds to first frame, and whether the sample's spoken audio is audible on the glasses while streaming. Post it into the S6 Devin session and in `docs/CALIBRATION.md` later.
- [ ] ElevenLabs: account → **Starter plan** ($1 first month) → API key → pick a calm default voice → note the `voice_id`.
- [ ] Meta Model API: `dev.meta.ai` → API key (Standard tier, never the contributor tier). Optional: apply for the Meta Global AI Developer Hackathon credits ($150, deadline Oct 25 11:59 PM ET).
- [ ] Modal: `pip install modal && modal setup`.
- [ ] Devin secrets store: `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `META_MODEL_API_KEY`, `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET`.
- [ ] Devpost: register the team and create the project page skeleton.

## 8:30–9:30 PM — fixture clips (two people, 20 minutes)
One teammate is **Marcus** (the person who gets enrolled); two others are **strangers** (never enrolled). Use the real first name of whoever plays Marcus in the spoken lines. Record **with the glasses themselves** (capture-button video, exported from the Meta AI app) if you can; otherwise a phone held at head height, portrait, pointing forward, not panning. Start and end each clip with 2 s of stillness. Consenting teammates only.

| File | Length | Action |
|---|---|---|
| `enroll_marcus` | 15 s | Marcus at 1–1.5 m facing the camera; slow head turns left ~20°, center, right ~20°, slight up and down; one smile |
| `approach_marcus` | 15 s | Marcus starts ~5 m away at the right edge, walks to 1 m centered, stands 3 s |
| `leave_marcus` | 12 s | Marcus at 1 m for 3 s, walks off to the left and out of frame; hold 5 s of empty frame |
| `strangers` | 15 s | Two or three strangers at 2–4 m; one walks across, one looks straight at the camera, one steps in to 1 m for 3 s then backs off |
| `mixed` | 20 s | Marcus at 2 m on the left, strangers center and right; people shuffle; one stranger walks in front of Marcus and Marcus reappears |
| `conversation` | 30–40 s with audio | Marcus at 1 m. Lines below. Marcus steps out of frame after his last line |
| `yes_reply` | 10 s with audio | Marcus at 1 m; 2 s silence; someone off-camera reads flatly "Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?"; Marcus waits a beat: "Yes, sure." Hold 2 s |
| `no_reply` | 10 s with audio | Same, but Marcus laughs: "Nah, I'm good." |
| `distance_calibration` | 10 s | Marcus stands on tape marks at 1 m, 2 m, 3 m for 3 s each, saying the distance aloud |

Lines for `conversation` (the phone holder plays Priya, closer to the mic):
```text
Priya:  Hi there!
Marcus: Hey, hi! I'm Marcus.
Priya:  Nice to meet you, Marcus. I'm Priya.
Marcus: What are you building?
Priya:  Glasses that tell me who is around me.
Marcus: Oh, that's awesome.
Priya:  Well, nice meeting you.
Marcus: Nice meeting you too, see you around.
```
- [ ] AirDrop to a Mac and transcode (keeps the set under ~60 MB):
```bash
for f in *.mov; do ffmpeg -i "$f" -vf scale=720:1280 -c:v libx264 -crf 26 -c:a aac -b:a 64k "${f%.mov}.mp4"; done
```
- [ ] HEVC copies for the glasses Mock Device Kit (video only):
```bash
for f in enroll_marcus approach_marcus mixed; do ffmpeg -i "$f.mp4" -c:v libx265 -tag:v hvc1 -an "${f}_hevc.mov"; done
```
- [ ] Transcripts for `FakeTranscriber`: `conversation.txt`, `yes_reply.txt`, `no_reply.txt` with lines `other: …` / `user: …` (the dialogue above; Marcus = other, Priya = user).
- [ ] Commit everything to `Familiar/Resources/Fixtures/` once S1 has created the folder and `fixtures.json`; fill in the expectations.

## 9:30 PM–3:30 AM — Devin builds in parallel; humans unblock
- [ ] When S1 is on `main`, start five sessions: **S2** `devin/02-perception.md`, **S3** `devin/03-audio-speech-voice.md`, **S4** `devin/04-app-memory-consent.md`, **S9** `devin/09-modal-embedding-endpoint.md`, **S6** `devin/06-glasses-source.md` (mock path). Each reads AGENTS.md automatically; paste its prompt.
- [ ] Answer Devin within minutes (sessions sleep after 30 idle minutes). One human on call per two sessions; the others sleep in shifts.
- [ ] Draft the Devpost text and the pitch (Meta track: human connection first, consent model second, Meta stack third; disclose Devin and every model).
- [ ] Pre-grant permissions on both demo phones once a build exists (camera, microphone, contacts, location); download the iOS 26 speech assets on Wi-Fi.

## 3:30–7:00 AM — integration and the device loop
- [ ] Start **S5** `devin/05-integration-demo.md` with the list of open PRs.
- [ ] Two Mac owners pull `main`, build to the two iPhones, run the Readiness screen, test Route A (phone mic + glasses A2DP) and Route B (glasses HFP), set the threshold from the live scores, calibrate distance bins at 1/2/3 m and the loudness split. File issues into the owning Devin session.
- [ ] Deploy Modal (`modal deploy modal/embed_server.py`), create proxy-auth tokens, put `MODAL_EMBED_URL`, `MODAL_KEY`, `MODAL_SECRET` into `Secrets.xcconfig` on the demo Macs.

## 7:00–9:30 AM — glasses pass and stretch
- [ ] S6 hardware pass: Developer Mode → "Connect glasses" in Familiar → approve in Meta AI → streaming → a cue plays through the glasses over A2DP. Record FOV, fps, latency in `docs/CALIBRATION.md`. Restart the app before each long session (Classic transport leaks memory).
- [ ] If the MVP is stable: **S7** `devin/07-stretch-who-is-talking.md`. **S8** `devin/08-stretch-elevenlabs-agent.md` only if everything else is done by 8 AM (it needs the agent created in the ElevenLabs dashboard first; instructions are in the prompt).

## 9:30–11:15 AM — rehearse, record, submit
- [ ] Rehearse the five demo steps three times at the actual table; fix lighting (no backlit faces); fix roles (wearer, Marcus, stranger, narrator).
- [ ] Record the demo video (this is also the Devpost video).
- [ ] Devpost: description with the consent model in every paragraph; Meta's accessibility exception named; tools and models disclosed (Devin, Claude Code for planning, InsightFace, Apple Vision/Speech/Foundation Models, ElevenLabs, Meta Model API); repo link. Confirm no key was ever committed: `git log -p | grep -iE 'sk_|xi-api|api_key' | head`.
- [ ] **Submit by 11:15 AM.**

## 1:30 PM — judging setup
- [ ] Both phones charged; glasses charged in the case; Modal `min_containers=1`; app restarted; People list empty; TTS cache warm; Readiness all green; start the glasses stream two minutes before judges arrive.
- [ ] After judging: Demo controls → reset people (wipes faces, clips and the contacts the app created).
