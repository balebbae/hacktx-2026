# Agent setup (ElevenLabs dashboard, about 5 minutes)

The app talks to one ElevenLabs Conversational AI agent when the wearer says something after the wake word that is not a built-in command (for example "Familiar, how many people are around me?"). The agent cannot see anything by itself; it calls the client tools below and the phone answers from what it already knows. Nothing but text leaves the phone.

The app also sends the system prompt as an override at the start of every session, so the demo works even if step 3 is skipped. Everything else below has to be set in the dashboard.

## 1. Open the agent

1. Go to https://elevenlabs.io/app/conversational-ai (sign in).
2. Open the agent **Familiar** (id `agent_9501m5rvznp2fqqb0htxc2r3s22m`). If it does not exist, click **Create agent → Blank agent** and name it `Familiar`.

## 2. Agent tab

| Setting | Value |
| --- | --- |
| First message | leave **empty** (the wearer speaks first) |
| Language | English |
| LLM | any fast model (Gemini 2.0 Flash or GPT-4o mini) |
| Temperature | 0.2 |

## 3. System prompt

Paste exactly:

```
You are a terse assistant for a blind wearer. Answer in at most 12 words. Use the client tools for anything about the room or the people in it: who_is_here, where_is(name), remember_them, set_mode(mode), call_person(name), text_person(name), mute. Repeat tool results almost verbatim. Never describe strangers beyond a count. Never guess identities. Never talk about faces or photos. The wearer is {{user_name}}; people they know: {{known_names}}.
```

`{{user_name}}` and `{{known_names}}` are dynamic variables the app fills in on every session. If the dashboard asks you to define them, add both as text with any placeholder default.

## 4. Voice tab

| Setting | Value |
| --- | --- |
| Voice | the same voice the app uses for cues (voice id in `Secrets.xcconfig` → `ELEVENLABS_VOICE_ID`; default is **Sarah**, `EXAVITQu4vr4xnSDxMaL`) |
| TTS model | **Eleven Flash v2.5** (`eleven_flash_v2_5`) |
| Stability / Similarity / Speed | 0.5 / 0.75 / 1.0 |
| Output format | leave default |

## 5. Advanced tab

| Setting | Value |
| --- | --- |
| Max conversation duration | **120** seconds (the app hangs up by itself at 90 s) |
| Turn timeout | **5** seconds |
| Client events | keep `agent_response`, `user_transcript`, `interruption` and `client_tool_call` ticked |

## 6. Security tab

| Setting | Value |
| --- | --- |
| Enable authentication | either is fine. **On** (private agent): the phone needs `ELEVENLABS_API_KEY` in `Secrets.xcconfig` and fetches a one-off conversation token. **Off** (public agent): the phone connects with the agent id alone. |
| Allowlist | leave empty |
| **Enable overrides** | tick **System prompt** and **First message** (the app sends the prompt above on every session) |

## 7. Tools tab: add seven client tools

For every tool: **Type = Client**, **Wait for response = On**, **Response timeout = 10** seconds. Parameter type is **String** everywhere; mark it **Required**. Keep the names exactly as written; the app matches on them.

| Name | Description to paste | Parameters |
| --- | --- | --- |
| `who_is_here` | Who is around the wearer right now. Returns a short sentence to repeat verbatim. | none |
| `where_is` | Where a known person is right now or was last seen. | `name` (String, required): first name of the person |
| `remember_them` | Start remembering the person in front of the wearer. The app asks that person for permission itself; just say "Starting." and stop talking. | none |
| `set_mode` | Change how talkative the cues are. | `mode` (String, required): one of `quiet`, `normal`, `chatty` |
| `call_person` | Open the phone dialer for a known person. Does not place the call. | `name` (String, required) |
| `text_person` | Open Messages to a known person. Does not send anything. | `name` (String, required) |
| `mute` | Mute the app's spoken cues. | none |

Click **Save** after each tool, then **Save** on the agent.

## 8. Check it

In the dashboard **Test agent** panel the tools will time out (nothing answers there); that is expected. On the iPhone, with the app running and the glasses or phone camera on, say:

> "Familiar, how many people are around me?"

Expected: the agent calls `who_is_here`, repeats the count (for example "Marcus ahead, close. Two other people."), and the session ends on its own about eight seconds after the answer. Cues resume within two seconds. The Judge view shows `agent: connecting → listening → thinking → speaking → ended (idle)` and the transcript.

## What the app sends and when

- Session start: prompt override, `user_name`, `known_names` (first names only), then the spoken phrase as text.
- Every 2 s while live: a silent context line such as `Visible now: Marcus ahead close; 2 other people.` (names only for people who consented; strangers are a count).
- Tool results: the same short phrases the app already speaks ("I don't know anyone called Zed.", "Calling Marcus.", "Muted.").
- Never: audio from the glasses, faces, photos, embeddings or anything about a stranger beyond a count.

## Hard limits in the app (not configurable)

- Not always-on: a session opens only for an unparsed wake-word phrase or the Judge-view button.
- Ends after the answer plus 8 s of silence, at 90 s, on "cancel", or when `remember_them` hands over to the consent flow.
- Refuses with "Not while streaming." while a glasses video stream is active (the glasses hold the mic).
- Pauses the app's audio engine for the session and restarts it on Route A (phone mic + glasses A2DP) afterwards.
