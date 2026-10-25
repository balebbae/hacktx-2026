# Agent setup (ElevenLabs dashboard, about 5 minutes) — optional

The default assistant is **Poyo on the vision model** (`PoyoBrain`): it sees the redacted view itself and needs no dashboard setup, only `META_MODEL_API_KEY` (or `VISION_*`). This page is for the alternative text-only ElevenLabs agent, enabled by setting the UserDefaults key `assistantBrain` to `elevenlabs`. Name the agent **Poyo**; the wake word is "Poyo".

The app keeps one ElevenLabs Conversational AI agent open for the whole session, in **text-only** mode. It reads the on-device transcript (no wake word needed), answers when the wearer asks something or clearly needs help, and replies `SKIP` (never spoken) otherwise. Its answers are spoken by the app's own voice through the glasses. Text-only is what lets it run while the glasses camera streams: a voice session opens Bluetooth HFP, and HFP ends the glasses stream. The agent cannot see anything by itself; it calls the client tools below and the phone answers from what it already knows.

The app sends the system prompt as an override at the start of every session, so the demo works even if step 3 is skipped. Everything else below has to be set in the dashboard.

## 1. Open the agent

1. Go to https://elevenlabs.io/app/conversational-ai (sign in).
2. Open the agent (id `agent_9501m5rvznp2fqqb0htxc2r3s22m`, created as `Familiar`; rename it to `Poyo`). If it does not exist, click **Create agent → Blank agent** and name it `Poyo`.

## 2. Agent tab

| Setting | Value |
| --- | --- |
| First message | leave **empty** (the app speaks first only when it has something to say) |
| Language | English |
| LLM | any fast model (Gemini 2.0 Flash or GPT-4o mini) |
| Temperature | 0.2 |

## 3. System prompt

Paste exactly (the app also sends it as an override):

```
You help {{user_name}}, a blind person wearing camera glasses. You receive text only and your replies are spoken. Messages starting with [to you] are addressed to you: always answer, in at most 12 words. Messages starting with [overheard] are the wearer talking to someone else: reply exactly SKIP unless the wearer clearly needs something you can give (where someone is, who is here, what is around); then answer in at most 12 words. Context updates say who is visible, what is around and what other people said; never reply to them. Use the client tools for anything about the room: who_is_here, where_is(name), describe_surroundings, remember_them, set_mode(mode), call_person(name), text_person(name), mute. Repeat tool results almost verbatim. Only these people may be named: {{known_names}}. Never name, describe or guess anyone else, even if you heard their name; say someone. Never talk about faces or photos. Never agree to remember anyone yourself: only the remember_them tool can, and the other person must say yes to it. Never say the name of this app.
```

`{{user_name}}` and `{{known_names}}` are dynamic variables the app fills in on every session. If the dashboard asks you to define them, add both as text with any placeholder default.

## 4. Voice tab

Not used: the agent runs text-only and the app speaks its replies with its own ElevenLabs TTS voice (`ELEVENLABS_VOICE_ID`, default **Sarah**).

## 5. Advanced tab

| Setting | Value |
| --- | --- |
| Max conversation duration | the longest allowed (the app reconnects by itself when it ends, and replays the last 90 s of transcript as context) |
| Client events | keep `agent_response` and `client_tool_call` ticked |

## 6. Security tab

| Setting | Value |
| --- | --- |
| Enable authentication | either is fine. **On** (private agent): the phone needs `ELEVENLABS_API_KEY` in `Secrets.xcconfig` and fetches a signed WebSocket URL (`/v1/convai/conversation/get-signed-url`). **Off** (public agent): the phone connects with the agent id alone. |
| Allowlist | leave empty |
| **Enable overrides** | tick **System prompt**, **First message** and **Text only** (the app sends `text_only: true` and the prompt on every session) |

## 7. Tools tab: add eight client tools

For every tool: **Type = Client**, **Wait for response = On**, **Response timeout = 10** seconds. Parameter type is **String** everywhere; mark it **Required**. Keep the names exactly as written; the app matches on them.

| Name | Description to paste | Parameters |
| --- | --- | --- |
| `who_is_here` | Who is around the wearer right now. Returns a short sentence to repeat verbatim. | none |
| `where_is` | Where a known person is right now or was last seen. | `name` (String, required): first name of the person |
| `describe_surroundings` | What is around the wearer: hazards first, then people, then the place and objects. Returns a short sentence to repeat verbatim. | none |
| `remember_them` | Start remembering the person in front of the wearer. The app asks that person for permission itself; say nothing more. | none |
| `set_mode` | Change how talkative the cues are. | `mode` (String, required): one of `quiet`, `normal`, `chatty` |
| `call_person` | Open the phone dialer for a known person. Does not place the call. | `name` (String, required) |
| `text_person` | Open Messages to a known person. Does not send anything. | `name` (String, required) |
| `mute` | Mute the app's spoken cues. | none |

Click **Save** after each tool, then **Save** on the agent.

## 8. Check it

In the dashboard **Test agent** panel the tools will time out (nothing answers there); that is expected. On the iPhone, with the app running and the glasses streaming, say (no wake word needed):

> "What's around me?" or "Poyo, how many people are around me?"

Expected: the agent calls a tool and the answer plays in the glasses while the camera keeps streaming (Judge view fps stays above 0). Small talk with someone else produces no reply. The Judge view's Agent panel shows `live` and the transcript (`user`, `tool`, `agent` lines).

## What the app sends and when

- Session start: prompt override, `text_only`, `user_name`, `known_names` (first names only), then the last 90 s of transcript as one context update.
- Whenever it changes (checked every 2 s): a context line such as `Visible now: Marcus ahead close; 2 other people. Around: Stairs ahead. Kitchen. Table, chair.` (names only for people who consented; strangers are a count; scene words come from an on-device allowlist that never includes people or clothing).
- The wearer's final transcript segments as `[overheard] …` turns; wake-word phrases that are not built-in commands as `[to you] …`; other people's speech as `Other person said: …` context.
- Tool results: the same short phrases the app already speaks.
- Never: audio, camera frames, faces, photos, embeddings, or anything about a stranger beyond a count. Nothing at all while a consent flow runs.

## Hard limits in the app (not configurable)

- Replies of exactly `SKIP` are dropped. Answers to `[to you]` turns interrupt like a command; unsolicited remarks queue behind cues and obey Mute.
- Nothing is spoken by the agent while someone is being asked for consent; the agent can start that flow (`remember_them`) but never decides it.
- The audio engine stays on Route A (phone mic + glasses A2DP) the whole time; the agent never touches the audio session.
