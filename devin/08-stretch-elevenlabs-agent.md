# Devin session S8 (stretch, gated) — ElevenLabs conversational agent for free-form questions (branch `feat/agent`; only if S5 is stable by 8 AM)

Read `AGENTS.md`. You own `Familiar/Voice/AgentSession.swift` and `Familiar/Flows/AgentToolRouter.swift`, and you may add the ElevenLabs package. Humans must first create the agent in the ElevenLabs dashboard (instructions below) and put `ELEVENLABS_AGENT_ID` in the Devin secrets. Time budget: 3 hours.

## Goal
"Familiar, …" followed by a phrase the command grammar does not understand opens a short conversation with an ElevenLabs agent that answers from the live scene through client tools, then ends. Never always-on: sessions start on demand and end after the answer, 8 s of idle, or 90 s.

## Dashboard (humans; paste the agent id and a screenshot summary into the PR)
Agent "Familiar": LLM of your choice; first message empty; system prompt: a terse assistant for a blind wearer; answers in ≤ 12 words; uses tools for anything about the room; never describes strangers beyond a count; never guesses identities; never talks about faces or photos. Settings: `conversation.max_duration_seconds` 120, `turn.turn_timeout` 5, ASR keywords = known names (passed as a dynamic variable), TTS model `eleven_flash_v2_5`, the same voice as the cues. Client tools (type Client, "Wait for response" on, timeout 10 s): `who_is_here()` → text; `where_is(name)` → text; `remember_them()` → text; `set_mode(mode)` → text; `call_person(name)`, `text_person(name)` → text; `mute()`. Security tab: public agent (no auth) for the hackathon; allow overrides for `prompt` and `first_message`.

## Swift
- Package `https://github.com/elevenlabs/elevenlabs-swift-sdk.git`, **exact `3.4.0`** (not the 4.0 alpha); `import ElevenLabs`.
- Start: `let conversation = try await ElevenLabs.startConversation(agentId: Secrets.elevenLabsAgentID, config: ConversationConfig(dynamicVariables: ["user_name": userName, "known_names": names.joined(separator: ", ")]))`. Before starting, pause `AudioEngineController` (stop the tap and the player); the SDK's LiveKit layer takes over the audio session (`.playAndRecord` with Bluetooth HFP allowed by default). Because that opens HFP, **never start the agent while a glasses stream is active**: refuse with "Not while streaming." After `endConversation()`, restart the engine on Route A.
- Send the wearer's phrase as text right after `onAgentReady`: `try await conversation.sendMessage(phrase)`. While active, push the scene silently every 2 s: `conversation.updateContext("Visible now: Marcus ahead close; 2 other people.")`.
- Tools: observe `conversation.$pendingToolCalls`; for each call `let params = try call.getParameters()`, route by `call.toolName`, then `try await conversation.sendToolResult(for: call.toolCallId, result: result)`; on failure `sendToolResult(for:result:isError: true)`. `remember_them` ends the agent session first, then calls `consentFlow.begin(confirmFirst: false)` and returns "Starting."
- End: when `agentState == .listening` for 8 s after the first answer, at 90 s total, or on "cancel" → `await conversation.endConversation()`.
- Judge view shows "Agent: speaking / listening" and the transcript (`onUserTranscript`, `onAgentResponse`).

## Tests
Router unit tests for each tool name with canned params; a fake conversation object for the lifecycle (start → message → tool → end). No network in tests.

## Definition of done for a human
"Familiar, how many people are around me?" → the agent answers using `who_is_here` → the session ends by itself → cues resume on the glasses within 2 s. Cost check: a 3-minute test is about $0.25 of agent time.
