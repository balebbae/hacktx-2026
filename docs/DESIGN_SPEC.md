# FAMILIAR
## Native iOS Experience & Visual Design Specification

**Version:** 1.2 · October 24, 2026  
**Platform:** iPhone, iOS native (SwiftUI) · optional Ray-Ban Meta glasses companion  
**Document type:** Product design system + interaction specification + implementation handoff  
**Design ambition:** An emotionally warm, technically magical, voice-first companion for people across the spectrum of visual impairment to feel included in the room.  
**Working product promise:** **Never miss your chance to say hello.**

> **Core source of truth:** The Familiar product concept supplied by the team. This document designs **Familiar**, a consent-first social-awareness experience; it is *not* a general navigation assistant, generic vision chatbot, mood reader, conversation recorder, or an autonomous assistant that contacts people. Features below marked **Prototype** or **Future / gated** must not be depicted as live without being implemented and validated.

---

# 0. THE ONE-MINUTE CREATIVE BRIEF

Build a premium, playful, impossibly polished native iPhone application whose signature is **Mimo**, a tiny living light creature that feels somewhere between a friendly expressive robot and a floating iridescent Muse-inspired orb. Mimo looks like a soft translucent animated volume, not a static circular logo. Inside the orb, luminous fluid gradients continuously drift. A pair of minimal expressive eyes, an optional tiny mouth, and almost imperceptible breathing give it personality.

The user should **feel accompanied, not monitored**. Familiar stays quiet most of the time. The orb acknowledges a wake word or tap, compresses subtly while listening, shimmers while processing, and gives a gentle confirming bounce when a known, *opted-in* person is nearby. It can also express uncertainty calmly; it must never imply it knows an identity when confidence is insufficient.

The aesthetic draws from the supplied image: pale warm-gray canvases, editorial typography, oversized soft gradients, floating white pill controls, rounded cards, sophisticated whitespace, and highly restrained navigation. Evolve the reference from a meditation UI into an **assistive social awareness product**: a warm, alive center for identity, people, consent, wearables, voice, and event awareness.

**North star:** The entire experience remains usable with the phone in a pocket and screen off, **and** presents an equally polished, legible enhanced-vision UI for people using residual vision, magnification, or large text. The app's visuals are a delightful companion to accessibility, never the only way to access functionality.

**Tagline options:**
- **Be part of the moment.** *(recommended)*
- The people around you, in your own way.
- Feel more at home in every room.
- More connection. Less guessing.

---

# 1. PRODUCT GUARDRAILS — NON-NEGOTIABLE

1. **Consent is product architecture.** Only individuals who have explicitly opted in may be enrolled and identified. Unknown people remain unknown. Do not show profiles, infer identities, or save images of bystanders.
2. **The privacy promise must be real.** The concept calls for face/voice representations to remain on the primary user's phone and never be transmitted to Meta or another server. Make this a hard technical requirement; don't send recognition media to a generic cloud vision or LLM API. Any cloud-backed non-identifying task must be separately disclosed and isolated.
3. **No unilateral enrollment.** A user cannot take a photo of someone and silently add them. The other person completes their own opt-in, or an explicitly approved verbal-consent enrollment procedure occurs. Do not ship a voice-consent workflow merely on the basis of automated speech recognition; verify compliance, explicit consent, revocation, and jurisdiction first.
4. **No emotion detection.** Detect only narrow observable events if technically validated and enabled: a wave, a nod, a visible smile, or a person leaving frame. Never tell users that someone is happy, attracted, bored, offended, trustworthy, or 'waiting for you to speak' as a fact.
5. **Uncertainty is safe.** When evidence is insufficient, say “Someone is nearby” or “I'm not sure who that is”; never hallucinate a name, distance, or intention. Approximate directions only if calibrated.
6. **Not a mobility aid.** Direction to people and large furniture may be offered as supplemental information, but never imply hazard detection or safe navigation. No obstacle-avoidance promises.
7. **Silent by default.** Never stream constant descriptions or talk over real people. Short cues: often 3–6 words. Accessible control over interruptibility.
8. **Wearables support is conditional.** Ray-Ban Meta pairing and camera/audio controls depend on current SDK and permission capabilities. A *demo prototype* can simulate a glasses feed, but UI must never falsely claim device connection.
9. **Platform-policy gate.** Do not implement or distribute facial or speaker identification through Meta glasses until Meta's applicable accessibility exception/approval and developer policies are checked and satisfied. A local simulation or manually confirmed identity demo is an alternative, clearly labeled.
10. **Blind users guide usability.** Real usability testing with blind and low-vision people is required before claiming the interface is accessible in practice. A blindfold-only sighted test is not equivalent.

---

# 2. WHO IT IS FOR / PRIMARY JOBS

**Primary user:** Blind or low-vision adult, comfortable with VoiceOver, participating in school, work, social gatherings, conferences, restaurants, and daily life. They may use glasses, an iPhone, a cane, or another mobility aid; don't presume one experience fits everyone.

**Secondary user:** A sighted or low-vision friend, classmate, family member, colleague, or event acquaintance who chooses to enroll. The system should make them feel respected, informed, and fully in control of consent.

**The six critical jobs:**

1. **Who is here?** On-demand roll call of enrolled contacts currently in view; use clock directions and qualitative distance only when supported.
2. **Who just arrived or left?** Short event-driven cues for opted-in contacts.
3. **Who is speaking?** Identify an opted-in speaker only if this capability is supported, permitted, calibrated, and above threshold; otherwise clearly acknowledge uncertainty.
4. **What changed nonverbally?** User-selectable, narrowly observable wave/smile/nod alerts, never emotions or intentions.
5. **Can I remember this person?** A fast, consent-first QR/NFC enrollment flow that the *other person* completes.
6. **Can I reconnect later?** Contact card, when/where met, and user-initiated native call/text actions.

**Social storytelling, not surveillance:** the hero action is “You can say hi first,” not “We know everyone in the room.”

---

# 3. VISUAL WORLD / ART DIRECTION

## 3.1 The feeling

**Keywords:** kind, animated, kinetic, intimate, calm, curious, futuristic, luminous, collectible, friendly, approachable, sovereign, quietly magical.

**Avoid:** medical-dashboard visual language, aggressive neon cyberpunk, generic AI-chat bubble UI, infantilizing cartoon mascots, giant status graphs, dense accessibility settings on the main screen, and overuse of Meta or competitor branding.

**Reference translation:**
- Keep the reference's **stone/off-white full-bleed background** and edge-to-edge curved surfaces.
- Keep **one dominant luminous gradient form** per screen.
- Keep **clean editorial text**, black or charcoal, not faded to the point of inaccessible contrast.
- Use **white translucent pills** for selected controls, but with a solid/opaque fallback under Increase Contrast.
- Use **intentional negative space** and a small number of high-value primary actions.
- Transform the static calming orb into **a warm expressive live companion**, never a childish assistant.

## 3.2 Color tokens

All color values are visual starting points and must pass contrast checks in the final rendered context.

| Token | Light | Dark | Purpose |
|---|---|---|---|
| `canvas.primary` | `#F7F6F3` | `#101116` | App background |
| `canvas.secondary` | `#EEEDEA` | `#191B22` | Elevated surfaces |
| `surface.card` | `#FFFFFF` | `#24262F` | Card / modal |
| `ink.primary` | `#17191D` | `#F7F7F9` | Headline and body |
| `ink.secondary` | `#555963` | `#CED0DA` | Support copy |
| `stroke.soft` | `#E4E5E8` | `#393B47` | Outlines |
| `accent.blue` | `#6D9CF5` | `#91B8FF` | Calm, neutral cue |
| `accent.lilac` | `#B59FFF` | `#C3B2FF` | Thinking / intelligence |
| `accent.teal` | `#57C9C1` | `#70DBD5` | Listening / connected |
| `accent.peach` | `#FFBCA8` | `#F5B7AE` | Warmth / contact |
| `status.success` | `#136C50` | `#79E4BB` | Explicit connection / enrolled |
| `status.warning` | `#975E16` | `#FFD18A` | Uncertain / setup needed |
| `status.danger` | `#B42336` | `#FF929C` | Revoke / delete |

Gradient presets *(behind high-contrast dark labels only when backed by an opaque surface)*:

- **Aurora idle:** `#9FD6F5 → #B0BDF6 → #D8B5F6 → #9BEBD4`, blurred, low saturation.
- **Listening:** `#6FD7CD → #80C4FB → #D3B9FE`, stronger teal bloom.
- **Thinking:** `#9C8AF9 → #6F8EF9 → #D3BAF6`, slowly braided.
- **Known person:** `#8ADFC8 → #A2CFFF → #FFD6B6`, one restrained warm flash.
- **Uncertain:** neutral silver-lilac, no red panic animation.

## 3.3 Typography

Use **SF Pro** through the system font APIs; **SF Rounded** sparingly for personality, small labels, and the companion's short responses. Do not bundle proprietary or extracted font binaries.

| Style | Base size / weight / line spacing | Use |
|---|---|---|
| Display | 38–44 pt, semibold, tight tracking | Welcome and big promise |
| Title XL | 30–34 pt, semibold | Screen titles |
| Title | 23–26 pt, semibold | Cards / modules |
| Body | 17–19 pt, regular | Critical descriptions |
| Supporting | 15–16 pt, regular | Secondary text |
| Micro label | 13–14 pt, medium | Supplementary metadata only |

Respect Dynamic Type up to accessibility sizes. Text must reflow; never clamp essential labels or reserve fixed-height cards for full-size Dynamic Type.

## 3.4 Spatial system

- **Base:** 4-pt increments; primary spaces 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48.
- **Horizontal margins:** 22–24 pt on standard iPhones; scale for small devices and landscape.
- **Hero card radius:** 32–40 pt; nested cards 20–24; controls 18–22; pills fully rounded.
- **Touch target:** minimum 44×44 pt, ideally 52–60 pt for major actions.
- **Bottom floating dock:** blurred/solid capsule with strong boundaries and VoiceOver grouping; leave safe-area clearance.
- **Tap feedback:** 0.97 scale for 100 ms, subtle haptic only if enabled; obey Reduce Motion.
- **Shadows:** ultra-soft, short spread, no heavy material-design elevation.

---

# 4. MIMO — THE LIVING AI COMPANION

## 4.1 Original visual identity

**Working mascot name:** **Mimo**. The app itself is Familiar; Mimo is the *visual embodiment of Familiar*, not a separate independent agent. “Familiar is listening,” not “Mimo is deciding who you should talk to.”

The mascot should evoke the approachable feel of conversational AI companions and the liquid, luminous visual language of Muse **without tracing or copying an existing mascot, face, shader asset, or Meta logo**. This is an original character designed to be ownable.

**Silhouette:** A floating slightly asymmetric blob, approximately a sphere with a soft-squircle tendency. It oscillates between 0.96 and 1.04 aspect ratio. No limbs by default. No hard outline. Delicate light scattering at the edge. At the center are two tiny highly legible expressive eyes, with an optional miniature curved mouth appearing only at appropriate moments.

**Body:** Render using layered liquid color fields with smoothly moving highlights, translucent depth, a faint Fresnel rim, blurred internal swirls, and gentle granular noise to keep it from looking like a cheap CSS gradient. Visual inspiration: translucent glass candy + an iridescent soap bubble + a friendly glowing robot.

**Eyes:** Two small dark navy-to-charcoal oval dots on lighter orb area; slightly uneven micro-movements and occasional blinks. Never use eye color alone to communicate state. Eye spacing about 0.28× orb diameter; each eye width 0.045× diameter; height 0.07× diameter. Expressions via eye height, position, rotation, and mouth curve, not exaggerated emoji faces.

**Mouth:** Tiny single curved dark mark at 15–20% the eye-to-eye width. Hidden in idle if it feels too human. Appears for delight or voice replies; never lip-sync with uncanny mouth movements.

**Spark details:** Subtle orbiting refractions or a tiny halo ripple on meaningful events; no constant confetti, no flashy rainbow strobes.

**Scale:** Home hero 240–280 pt diameter on standard phones; listening overlay 170–220; mini avatar 46–64 in headers; Live Activity uses a simplified static emblem.

## 4.2 Expression states — essential behavior

| State | Movement | Face | Color | Companion line / semantics |
|---|---|---|---|---|
| Idle | Slow breath; ±3% scale every 5–7s | Relaxed blinking | Aurora | “Ready when you are.” |
| Listening | Slight inward squash synchronized to input amplitude, **not a recorded voiceprint** | Attentive eyes, lean forward | Teal-blue | “Listening.” |
| Thinking | Slow clockwise fluid curl, no spinner | Eyes glance upward briefly | Lilac-blue | “One moment.” |
| Responding | One tiny bounce on first word | Soft warm smile | Blue-peach | Spoken response |
| Known contact nearby | Single small warm pulse | Friendly eye widen | Peach-teal | “Maya, two o'clock.” |
| Consent waiting | Near-still, respectful | Neutral face | Soft lilac | “Waiting for Maya's choice.” |
| Enrolled / consent accepted | One small happy bob, no fireworks | Small smile | Teal-peach | “Maya chose to connect.” |
| Unknown person | No excitement | Neutral | Neutral aurora | “Someone is nearby.” |
| Uncertain identity | Small settle, no false upbeat pulse | Gentle neutral | Silver-lilac | “I'm not sure who that is.” |
| Privacy paused | Motion nearly stopped | Eyes close or hide | Desaturated neutral | “Awareness paused.” |
| Device disconnected | Subtle downward drift; no alert loop | Neutral | Gray-blue | “Glasses disconnected.” |
| Audio muted | Orb remains present, no speaking animation | Neutral | Muted teal | “Voice cues off.” |
| Error | One tiny soft wobble, then rest | Apologetic-neutral | Calm neutral | Plain non-alarming explanation |

**Do not anthropomorphize capabilities:** the orb can convey listening or device state, but cannot suggest it has feelings, is sentient, or has evaluated social emotions.

## 4.3 Shader / rendering pipeline

**Preferred native path:** SwiftUI view containing an `MTKView` backed by Metal fragment shaders; wrap through `UIViewRepresentable`. Alternative prototype: layered `AngularGradient`, `MeshGradient` where OS-supported, `Canvas`, blur layers, and `TimelineView` for animation. Provide a static accessible asset for older devices and Reduce Motion.

**Shader composition (conceptual):**

1. Signed-distance rounded blob boundary, driven by very low frequency 2D/3D noise.
2. Interior field coordinates warped by 2–3 sine-based vector flows, each with distinct time scales.
3. Four or five pigment lobes at low alpha, blended smoothly in linear color space.
4. Rim glow based on distance-to-edge/Fresnel approximation, plus subtle specular highlight.
5. Light refraction / fake volumetric layering using 2–3 parallax fields, constrained GPU cost.
6. Separate face layer above shader in native SwiftUI so eye geometry is crisp and accessible.
7. Optional response to speech *amplitude only*, rate-limited and low-pass filtered; no cloud transmission of microphone data for this effect.

**Animation pseudo-parameters:**

```text
blobScale = 1 + 0.025 * sin(time * 0.9)
noiseWarp = 0.045 * fbm(uv * 2.0 + time * 0.08)
flowA = sin(uv.y * 3.0 + time * 0.32)
flowB = cos(uv.x * 2.7 - time * 0.21)
listenPulse = lowpass(microphoneAmplitude) * 0.08
knownPersonPulse = easeOut(expDecay(eventTime))
```

**Performance budget:** target 60 FPS if sustainable, gracefully fall to 30 FPS on low power. Pause off-screen rendering, cap resolution based on view size and display scale, avoid allocating textures per frame, reduce processing when thermal state is elevated. Keep animation decorative and event handling responsive.

**Reduced Motion:** show static gradient orb with **textual and auditory state labels**; event changes use simple crossfades or no animation. **Reduce Transparency:** replace translucent docks and orb backing with opaque surfaces. **Differentiate Without Color:** every state has text/speech/semantic labels.

## 4.4 Voice personality

Voice should feel **competent, warm, discreet, and respectful**. More trusted earbud than playful robot. Silence is intentional, not a bug. Do not speak over someone unless a high-priority enabled cue demands it.

- Desired sound: concise, conversational, low-drama, natural pacing.
- Good: “Maya, on your right.” “Jordan just left.” “I can't tell who that is.”
- Bad: “Fantastic news! I've identified your friend Maya approaching at 2 o'clock!”
- Avoid speaking emotion guesses, speculation, or clinical labels.
- **User settings:** voice on/off, cue verbosity (Quiet / Normal / Chatty), speech rate, volume, left/right spatialization where possible, whether interruptions are allowed.
- Audio policy: event deduplication, configurable cooldowns, easy one-gesture pause; do not turn people into a constant notification feed.

---

# 5. INFORMATION ARCHITECTURE

**Primary bottom navigation (three destinations + central companion):**

```text
FAMILIAR
├── Home (Mimo / present moment)
│   ├── On-demand roll call
│   ├── Connected status / audio status
│   ├── People nearby (enrolled only)
│   ├── Most recent actionable social cue
│   ├── Pause awareness / resume
│   └── Hands-free voice interaction
├── People
│   ├── Enrolled people
│   ├── Search
│   ├── Contact details / call / message
│   ├── Add with consent (NFC / QR)
│   ├── Pending invitations
│   ├── Manage / delete
│   └── Consent preferences
├── Moments
│   ├── Ephemeral event summary (default off or limited)
│   ├── Last seen contextual information
│   ├── Reconnect prompts (not auto-sent)
│   └── Personal shortcuts
└── Settings / devices (avatar or top right)
    ├── Glasses and phone input
    ├── Voice & cue preferences
    ├── Accessibility
    ├── Privacy / consent / deletion
    ├── Device permissions & battery
    └── Help and feedback
```

**Naming decision:** Prefer **People** over Contacts in bottom nav; prefer **Moments** over Analytics or Progress. There must be **no social scoring, reputation graphs, or friendship streak pressure**.

**Core navigation:** Home / People / Moments in a floating dock. Small rounded status icon in the header opens Device & Privacy, never a large cluttered settings gear. The main CTA is Mimo's large “Ask Familiar” voice interaction area. Keep People and Moments accessible from VoiceOver navigation, and keep important actions in standard native semantics.

---

# 6. SCREEN-BY-SCREEN NATIVE DESIGN

## Screen 01 — First launch / opening film

**Visual:** Full-page warm ivory canvas. Mimo fades into view in the upper middle, begins one slow breath and blinks. Underneath: a spacious, two-line hero.

**Headline:** “Feel part of every moment.”  
**Supporting text:** “A quieter way to know who's nearby, reconnect with people you know, and stay in the conversation.”  
**Primary CTA:** “Get started” (solid charcoal pill; 56 pt tall).  
**Secondary:** “How privacy works” text button; no deceptive burying of consent information.

**Onboarding voice alternative:** VoiceOver can complete this entire experience without seeing the animation; optional spoken intro is not auto-played unless user chooses it.

## Screen 02 — What Familiar can and cannot do

Three cards with quiet diagrams/icons and explicit semantic labels:

1. **Recognize your people** — “Only people who agree to be remembered.”
2. **Share small social cues** — “Names, direction, arrivals, and selected gestures. Never feelings or intentions.”
3. **Stay in control** — “Pause instantly. Delete anytime. Nothing needs to happen behind your back.”

At bottom, one trust line: **“Familiar is not a navigation or safety device.”**

## Screen 03 — Accessibility-first preferences

Ask only essential settings upfront, as independent accessible native controls:

- How would you like updates? **Audio cues**, **Haptics** (where available), **On-screen text**; multiple selection permitted.
- How often? **Quiet** (on demand), **Normal** (approach / leave), **Chatty** (plus enabled gestures).
- How would you like to interact? **Voice + button** / **Button-first**.

All choices editable later. Preselect a conservative Quiet or Normal default, disclose what is triggered automatically.

## Screen 04 — Privacy / capability readiness

Show steps as clear cards, not alarming OS-permission walls:

**Microphone** — spoken commands if chosen.  
**Bluetooth** — communicate with glasses if supported.  
**Camera** — local visual processing when supported and explicitly activated.  
**Contacts** — only if user requests writing a new phone contact; no bulk contact harvesting.  
**Notifications** — optional; not necessary for social cues.

Require permission only contextually; users can explore the app without glasses. Show a real hardware-policy readiness state, e.g., “Device capability not available in this prototype” instead of a deceptive fake success.

## Screen 05 — Connect your glasses

**Visual:** Hero illustration or lightweight 3D/2D device silhouette paired with Mimo floating nearby. Thin glowing dotted line animates only during actual pairing.

**Headline:** “Let’s connect your glasses.”  
**Status variants:** Not detected / Searching / Pairing / Connected / Needs permission / Unsupported capability.  
**Primary:** “Connect glasses” (initiates real supported SDK flow).  
**Secondary:** “Continue with my phone” (functional fallback).  
**Helper:** “You can finish setting this up later.”

**Pairing behavior:** If the official toolkit exposes a previously trusted device and supports reconnection, offer auto-reconnect after explicit opt-in; don't silently initiate camera capture on connection. Glasses connection is separate from awareness recording/processing.

## Screen 06 — Home / the hero experience

**This must be the signature portfolio-worthy screen.**

### Composition

- Top-left small `Familiar` wordmark; not oversized, no fake Meta affiliation.
- Top-right round button with **Glasses connected** / **Phone mode** and privacy status; accessible descriptive label.
- 30–40 pt breathing space.
- Center 245–275 pt Mimo, visually the whole emotional focus of the screen.
- Under Mimo: small dynamic eyebrow `YOUR MOMENT` (or `AWARENESS IS ON`).
- Big contextual headline: **“You're in good company.”** when recognized people available; default **“Here with you.”**
- Clear support text: “Ask who's here, or simply enjoy the moment.”
- Hero CTA, very large: **“Who's here?”**
- Secondary horizontal mini-control: **Pause** | **Voice cues: On**.
- A compact card near bottom, only if relevant: **“Maya · 2 o'clock · nearby”** and optional **“Say hi”** guidance; NEVER silently call/message.
- Floating Home / People / Moments dock with distinct symbols and labels.

### Empty / first-use state

“Only people who choose to connect will show up here.”  
CTA **“Invite your first person.”**

### Active state

A small text band reads “2 of your people nearby” and explicitly differentiates approximate visibility from certainty. A small dedicated `Heard 1 minute ago` disclosure may be included in a contact detail, but avoid timestamps on everything.

### Voice interaction

Tap Mimo **or** primary voice button. Ask: “Who's here?”, “Is Maya close by?”, “Mute for a bit”, “Call Sam.” Mimo switches from idle to listening. For speech capture, display **Listening** with large Stop control. Read transcript only if local and user opted in; don't keep a history by default.

## Screen 07 — Listening overlay

This is the most cinematic screen after Home.

- Dim ivory backdrop gently; expand Mimo to 220 pt.
- Mimo's inner liquid moves more actively while listening, eyes attentive.
- Under orb, a single waveform/warm pulsing underline tied to local audio energy (decorative).
- Text **“Listening…”** in 30 pt.
- Supporting examples: “Who’s here?” · “Pause awareness” · “Call Maya.”
- Huge **Stop listening** action with native semantics.
- Accessibility: focus enters “Listening. Say a command or stop.” Provide optional spoken beep; avoid capturing audio indefinitely.

## Screen 08 — Roll call / who's here

**Never a camera face gallery.** The goal is a useful spoken overview.

- Title: **“Your people nearby”**.
- One-line summary: “2 known people in view. Others remain unnamed.”
- Distinct accessible rows, e.g.:
  - Round gradient contact monogram / consent-approved avatar icon; **Maya**; “2 o’clock · close”; “Recognized with high confidence.”
  - **Jordan**; “10 o’clock · across the room.”
- Each row reads as one sensible VoiceOver element and supports “More details.”
- Bottom button: **“Hear roll call again.”**
- If no known people: “No enrolled contacts detected right now. You can ask again anytime.”
- If detection unavailable: “Awareness isn't available in phone mode” with a real alternate path, not fabricated contacts.
- If approximate spatial calibration fails: omit clock direction and distance entirely.

## Screen 09 — Arrival / departure heads-up

**Pattern:** Small, restrained, temporary in-app overlay with Mimo mini form and a 1-line cue.

**Examples:** “Maya, coming from your right.” / “Sam just left.”

- No full-screen modal during an interaction.
- Haptics optional and distinctive, never urgent-alarm styled.
- Accessibility announcements rate-limited and queue-aware; don't interrupt user mid-word if priorities are low.
- Debounce camera churn to avoid “left/returned/left” spam.
- Automatically dismiss visually after 4–6 seconds, but retain access through an on-demand summary only if user enabled it.

## Screen 10 — People / contact directory

**Visual:** Elegant pale background with dense-but-readable rows on white cards.

- Top header: **“Your people.”** Subtext: “Only people who said yes.”
- Search field.
- Visually distinctive **Add someone** gradient-border pill (not high-saturation fill).
- Filter chips: All / Recent / Nearby (nearby only while awareness active and supported).
- Contact rows: name, optional shared place of meeting, enrollment status, explicit remove action through detail screen.
- No relationship scores, smile frequency statistics, face thumbnails captured secretly, or ranking people by attention given to user.
- Empty state visually includes mini Mimo and a friendly line: “The best connections start with a hello.”

## Screen 11 — Person detail

**Hero:** Large user-provided/consent-approved image or soft monogram. Name large and readable. Context line: “Met at HackGT · Sep 2026” (only when entered/confirmed by user; no inferred location tracking).

**Actions:** **Call** / **Message** / **Where we met** / **Remove from Familiar**. Call and Message present an understandable confirmation or navigate to native action; never auto-send texts.

**Privacy note:** “Maya can remove their enrollment whenever they choose.”

**Data clarity:** Show only fields actually stored: display name, optional phone, consent event, optionally local face/voice template, optional meeting note, created date. Do not build a conversation-history tab.

## Screen 12 — Add person / consent method picker

Split into two premium cards:

**A. Let them join with their phone** *(recommended MVP)*
- Show a large QR code or an NFC tag setup action; the other person opens a no-install opt-in page on their own phone.
- Copy: “They choose what to share. You can't enroll someone without them.”
- Button: **“Show invitation code.”**

**B. Ask them out loud** *(Future / gated)*
- Clearly labeled unavailable until approved and verified.
- Use a staged demo mode if essential; never portray automatic consent understanding as an approved live feature.

## Screen 13 — QR / NFC invitation

- Ivory canvas, large centered QR on solid white with enough clear margin, easy to scan.
- Accessible 6–8 character fallback short code. For blind primary users, offer **“Read invitation instructions aloud”**.
- Text: “Ask your friend to scan or tap. It only takes a moment.”
- State: Waiting / Invitation opened / Consent granted / Declined / Expired / Cancelled.
- Mimo floats small near invitation text, remains subdued.
- The QR must expire; no indefinite public link containing biometrics.

## Screen 14 — Other person's one-page enrollment web view

Although the companion is native iOS, **the other person's onboarding must run in Safari/Chrome on iPhone or Android, with no installed app**, matching the source concept.

**Mobile web UI must visually mirror the native app:** white/ivory background, small Mimo emblem, generous vertical spacing.

**Page flow:**
1. “Priya would like to recognize you next time you meet.”
2. Explicit explanation: what is collected, where stored, who can access it, how to revoke.
3. Enter name; optional phone; selfie only if supported/policy-approved, with explicit camera permission and informed consent.
4. Affirmative unchecked checkbox or equivalent explicit consent confirmation; not bundled consent.
5. **“Allow Priya to remember me.”**
6. Clear success page and persistent **Remove my enrollment** mechanism.

**Critical architecture caveat:** A no-install website capturing a selfie and delivering it to a local-only phone database conflicts with a literal “nothing about the person is ever sent to a server” claim if relay services are used. Choose an auditable end-to-end-encrypted delivery path whose server cannot access biometric content, or use direct peer-to-peer local transfer. If even encrypted biometric upload violates the team's stated privacy promise, require local transfer and accurately describe its limitations. Do not state both claims unqualified.

## Screen 15 — Enrollment completed

- Mimo gives a restrained happy movement.
- Text: **“Maya chose to connect.”**
- Supporting: “You'll be able to recognize Maya when this feature is available and active.” (or verified functionality in a real build).
- Button: **“View Maya”**.
- No automatic camera activation.

## Screen 16 — Moments (lightweight, optional)

**Purpose:** Help users *reconnect*, not surveil or narrate their social history.

- Top: **“People make the moment.”**
- Cards: “Recently added,” “Your personal notes,” “Call someone,” “Connections you chose to remember.”
- Avoid automatic social activity logs by default. The reference concept expressly says Familiar is **not a memory archive**; Moments should not store unconsented encounter histories or conversation transcripts.
- If product scope feels bloated, remove the Moments tab entirely for MVP and keep Home / People / Settings.

## Screen 17 — Settings, voice, and awareness

**Groups:**

- **Awareness:** Pause/resume; automatic cues Quiet / Normal / Chatty; presence detection; each gesture cue separately enabled.
- **Speech:** Voice cue enable, volume, rate, side-specific playback where supported, interruptibility.
- **Accessibility:** Text size uses system setting, Reduce Motion, high contrast, descriptive sounds, haptic patterns, VoiceOver tutorial.
- **Device:** Connected glasses / battery only if reliable / reconnect / test sound / phone mode.
- **Privacy:** Local records, enrolled contacts, revoke/remove, erase all, export limited non-biometric contact fields if user requests, transparency explanations.
- **Support:** What Familiar can and cannot do, permissions, test accessibility, provide feedback.

No mysterious “AI intelligence score” or unexplainable system confidence slider accessible to users; confidence is an engineering safety threshold.

## Screen 18 — Global pause / safe state

One gesture or visible primary button must immediately pause all app-initiated live sensing and event cues, within platform constraints.

- Mimo becomes neutral and rests.
- Big text **“Awareness paused.”**
- Primary: **“Resume awareness”**.
- Secondary: **“Why am I seeing this?”**
- Show an honest note if glasses hardware camera is separately recording due to another app: Familiar can only stop its own sessions and can't guarantee the entire device camera stops.

---

# 7. CORE USER JOURNEYS / STORYBOARDS

## Journey A — Campus greeting

1. Priya has chosen Normal cues and explicitly started an awareness session.
2. A consenting, already-enrolled friend enters a supported camera view.
3. Recognition meets the conservative threshold; system emits one cue: **“Jordan, eleven o’clock.”**
4. Priya turns and chooses how to greet Jordan. Familiar remains silent.
5. If recognition isn't reliable, no identity is announced.

**Success:** Priya can initiate the social interaction; Familiar is not the center of it.

## Journey B — New contact at a career fair

1. Priya finishes a conversation with Marcus and chooses “Add someone.”
2. She presents a QR or NFC card.
3. Marcus sees exactly what Familiar will store and independently opts in.
4. Marcus provides a name and optional contact info; transfer and storage follow the declared privacy architecture.
5. Priya hears **“Marcus chose to connect.”**
6. Later, Priya can say “Call Marcus” to initiate a normal phone action, with confirmation.

**Success:** Enrollment is understandable, fully voluntary, quickly completed, and revocable.

## Journey C — Dinner with friends

1. Priya switches Chatty on for a short session.
2. Known friends' verified wave/nod/smile cues may be emitted under the enabled settings.
3. Familiar says **“Maya waved from your left.”** if recognition and gesture detection are validated.
4. Familiar never says “Maya is bored” or “They're all waiting for you” based on inferred intent.
5. Priya taps Pause to stop cues immediately.

**Success:** More context with less interruption.

## Journey D — Stranger in view

1. An unknown person enters the camera view.
2. Familiar may say “Someone nearby” on explicit request.
3. It does not identify, profile, characterize, record, or generate suggested approaches to that stranger.
4. If the person wants to opt in, the user opens the separate enrollment flow.

**Success:** Privacy is apparent, not an invisible backend assumption.

---

# 8. MOTION / SOUND / HAPTIC LANGUAGE

**Motion principles:** express state, never demand attention; easing `spring(response: 0.44, dampingFraction: 0.78)` for tiny Mimo motions, `easeInOut` for background diffusion. No large bounces while real people speak.

| Event | Visual | Haptic | Audio |
|---|---|---|---|
| App ready | slow breathe | none | none |
| Listening starts | teal inward pulse | one light | optional short activation tone |
| Command accepted | one soft micro-bob | one light | spoken response if enabled |
| Known contact enters | warm single halo | optional double-light | concise name and direction |
| Contact leaves | halo fades | optional single-light | “Maya left.” |
| Consent accepted | gentle upward bob | one success-like pattern | “Maya chose to connect.” |
| Identity uncertain | no positive confirmation | none | “I'm not sure who that is.” |
| Paused | orb settles and desaturates | one light | “Awareness paused.” |
| Error / loss of connection | static neutral indication | one soft warning, not repeated | “Glasses disconnected.” only if useful |

Respect silent mode, headphone routing, hearing needs, and user-set audio preferences. Spatialized speech should **only** be used when left/right direction actually maps to a reliable coordinate system. Haptic output from glasses must be available in hardware; don't suggest every Meta device can vibrate.

---

# 9. ACCESSIBILITY ACCEPTANCE CRITERIA

**Familiar isn't accessible because the brand helps blind people; it is accessible only if blind people can operate it independently.**

## VoiceOver

- Every icon button has an explicit meaningful accessibility label and hint; e.g., `“Pause awareness. Stops Familiar's live sensing and cues.”`
- Full onboarding, pairing, invitation, contacts, revoke, resume, device status, and errors are operable without visual cues.
- Mimo is one decorative image excluded from focus unless its status changes, in which case provide a separate clearly labeled status text. Never announce every frame of an animation.
- Contact rows announce a logical single summary: “Maya. Two o'clock, close. Enrolled contact. Double-tap for details.”
- Use accessibility focus changes deliberately and sparingly; no surprise focus jumps during alerts.
- Dynamic announcements respect focus, speech already in progress, and cue throttling.
- QR enrollment includes a shareable URL/code and spoken instructions; never require the blind person to visually verify the QR.
- Confirmation dialogs identify the target contact before removal.
- Test with VoiceOver rotor navigation, Switch Control, Voice Control, keyboard where relevant, and larger text.

## Low vision

- Support dark mode, high contrast, large text, 200%+ text resizing scenarios, visible focus and solid backgrounds behind important text.
- All core text must meet WCAG AA-equivalent contrast intentions (4.5:1 for ordinary text; 3:1 for large text/non-text UI elements as applicable); verify with actual rendered colors, not just token assumptions.
- Never rely on pastel-on-pastel; the gradient avatar does not carry essential information alone.
- No fixed-height clipping at Dynamic Type accessibility sizes.
- Touch targets ideally ≥ 52pt for hero actions.

## Cognitive / sensory

- Disable excessive animations on Reduce Motion.
- Avoid unrequested sound during onboarding.
- Keep cues predictable and short. Provide a cue tutorial / test mode.
- Support manual control as an alternative to voice commands.
- Use plain language: “Who’s here?” rather than “Start multimodal perception inference.”

## User testing

Recruit blind and low-vision participants with a range of preferences; test with real social contexts and consented volunteers. Capture task success, error rates, false-positive identities, interruptions, comfort, and whether people feel empowered or embarrassed. Do not report invented validation numbers.

---

# 10. NATIVE SWIFT / SWIFTUI IMPLEMENTATION BLUEPRINT

## Suggested structure

```text
FamiliarApp/
  App/
    FamiliarApp.swift
    AppEnvironment.swift
    AppRouter.swift
  DesignSystem/
    Tokens/
      FamiliarColors.swift
      FamiliarTypography.swift
      FamiliarSpacing.swift
    Components/
      FamiliarButton.swift
      StatusPill.swift
      ContactRow.swift
      FloatingTabBar.swift
      GradientCard.swift
      AccessibleToast.swift
      DeviceStatusChip.swift
  Companion/
    MimoView.swift                 // SwiftUI state machine wrapper
    MimoMetalView.swift            // UIViewRepresentable / MTKView
    MimoRenderer.swift             // shader pipeline, animation time
    MimoShaders.metal
    MimoExpressionView.swift       // eyes, mouth, blinking
    MimoState.swift
    MimoReducedMotionView.swift
  Screens/
    Onboarding/
      WelcomeView.swift
      CapabilityDisclosureView.swift
      AccessibilityPreferencesView.swift
      DeviceSetupView.swift
    Home/
      HomeView.swift
      VoiceOverlayView.swift
      RollCallView.swift
      NearbyContactCard.swift
    People/
      PeopleView.swift
      PersonDetailView.swift
      InvitePersonView.swift
      EnrollmentStatusView.swift
    Moments/
      MomentsView.swift
    Settings/
      SettingsView.swift
      AwarenessSettingsView.swift
      AccessibilitySettingsView.swift
      PrivacyView.swift
  Features/
    Awareness/
      AwarenessCoordinator.swift
      PresenceEvent.swift
      DetectionConfidencePolicy.swift
      CueScheduler.swift
      SessionState.swift
    Recognition/
      OnDeviceRecognitionService.swift
      OptInIdentityStore.swift
      PersonMatcher.swift
    Speech/
      VoiceCommandCoordinator.swift
      SpokenCueQueue.swift
      AudioSessionManager.swift
    Wearables/
      WearableConnectionService.swift
      MetaWearablesAdapter.swift   // only documented, authorized SDK calls
      PhoneCameraAdapter.swift
      MockDeviceAdapter.swift
    Enrollment/
      EnrollmentCoordinator.swift
      ConsentRecord.swift
      EnrollmentTransport.swift
      RevocationCoordinator.swift
    Data/
      ContactRepository.swift
      LocalSecureStore.swift
      DataDeletionService.swift
  Assets/
    MimoStatic.imageset/
    OnboardingIllustrations/
  Tests/
    VoiceOverUITests/
    EnrollmentConsentTests/
    RecognitionSafetyTests/
    PrivacyDeletionTests/
    CueSchedulingTests/
```

## Architecture decisions

- **SwiftUI** for all screens, native sheets, navigation, controls, focus management, accessibility semantics, and Dynamic Type.
- **Metal** for Mimo's shader, separate from app logic. Use a highly performant fallback rendering path.
- **MVVM / feature services** with async/await, dependency injection, and deterministic mock adapters. Do not entangle the avatar with camera state, recognition code, or privacy decisions.
- **Local data:** encrypted storage for sensitive templates and consent records; Keychain-managed encryption keys; minimal contact metadata. Set explicit data retention/deletion rules and verify secure removal behavior rather than asserting impossible forensic deletion guarantees.
- **Recognition:** only an on-device, platform/policy-approved implementation. Never send biometric templates to an LLM for matching. Thresholding should prioritize avoiding false identifications; consider multiple frames and identity confirmation.
- **Speech:** authorized audio capture with clear state and easy stop; local processing when feasible. If any speech processing leaves the device, the privacy statement must accurately explain what and why.
- **Meta SDK:** build a narrow adapter using only capabilities verified in the team's environment; keep a clearly labeled phone/simulator mode.
- **Contacts:** use standard iOS Contacts framework only after contextual permission and only for explicit saves/edits.
- **No background camera fantasy:** iOS and third-party glasses impose background/foreground, power, privacy, and session constraints. Reconnect and capture behavior must be validated on actual devices and should degrade gracefully.

## State model

```swift
enum FamiliarAwarenessState {
    case off
    case requestingPermission
    case starting
    case active
    case paused
    case unavailable(reason: String)
}

enum MimoState {
    case idle
    case listening
    case thinking
    case speaking
    case knownContactCue
    case waitingForConsent
    case success
    case uncertain
    case paused
    case deviceDisconnected
    case error
}

enum CueVerbosity: String, CaseIterable {
    case quiet, normal, chatty
}
```

**Important:** never use Mimo animation state as a substitute for verified device sensing state. Drive Mimo from the application's authoritative state machine.

## Example data contracts

```json
{
  "person_id": "local-random-id",
  "display_name": "Maya",
  "phone_number": null,
  "consent_status": "active",
  "consent_method": "self_enrollment",
  "local_template_reference": "encrypted-local-reference-or-null",
  "meeting_note": "Met at a campus event",
  "created_at": "local-date",
  "revoked_at": null
}
```

```json
{
  "event_type": "known_contact_entered",
  "person_id": "local-random-id",
  "direction": "two_oclock",
  "distance_band": "near",
  "confidence_band": "high",
  "timestamp": "event-time",
  "eligible_for_spoken_cue": true
}
```

Use typed Swift models in production; these JSON examples are an interface description only. Never expose identity events to third-party analytics.

---

# 11. DESIGN DELIVERABLES / FIGMA OR APP PROTOTYPE SHOT LIST

Produce realistic, pixel-perfect phone designs at a common iPhone artboard width (e.g. 393 pt), plus scalable variants and Dynamic Type screenshots. Each must include status bar, safe areas, and plausible content.

**12 must-have visual frames:**

1. Welcome / Mimo first greeting.
2. Privacy promise / consent cards.
3. Accessibility preferences.
4. Device pair / phone fallback.
5. **Home idle** — full hero Mimo.
6. **Home active** — someone nearby.
7. **Listening overlay** — Mimo fluid motion / speech waveform.
8. **Roll call** — clear accessible known-person rows.
9. **People directory** — modern search and cards.
10. **Invite person** — privacy-first QR flow.
11. **Person details** — contact actions / revocation.
12. **Paused or disconnected state** — honest fallback.

**Additional motion work:**
- 4–6 second looping Mimo idle animation (silent).
- Listening-to-thinking-to-speaking sequence.
- One contact-arrival cue.
- Consent-pending-to-confirmed transition.
- Reduce Motion static equivalent.

**Brand assets:** Mimo shader parameters, original face geometry, app icon (orb plus tiny eyes; highly recognizable at 60px), splash screen, 3 monochrome icons, empty state illustration, contact monogram palette. Never use the Meta infinity icon as Familiar's app icon or imply official Meta branding.

---

# 12. MICROCOPY / CONTENT DICTIONARY

| Context | Preferred copy | Avoid |
|---|---|---|
| Idle | “Here with you.” | “Scanning everyone around you.” |
| Roll call | “Who’s here?” | “Identify faces.” |
| Known entry | “Maya, two o’clock.” | “Target acquired.” |
| Uncertainty | “I’m not sure who that is.” | Guessing a name |
| No contacts | “Only people who say yes appear here.” | “No faces found.” |
| Invite | “Let them choose to connect.” | “Capture their profile.” |
| Consent success | “Maya chose to connect.” | “Face saved!” |
| Pause | “Awareness paused.” | “Surveillance stopped.” |
| Device unavailable | “Glasses aren't connected. Try phone mode.” | “We're watching anyway.” |
| Privacy | “You decide when Familiar listens.” | “Always-on intelligence.” |
| Error | “I couldn't confirm that.” | “AI failed recognition.” |
| Delete | “Remove Maya from Familiar?” | Ambiguous “Delete” |

**Pronouns / personalization:** Avoid assuming gender, age, vision level, or preferred language. Ask for names and pronunciation when useful, but never infer demographic properties from a face.

---

# 13. INTERACTION DETAILS / EDGE CASES

1. **Two people with the same name:** speak distinguishing user-provided nickname only when stored; otherwise ask user to review contact, never infer.
2. **Unknown contact wearing similar clothes:** clothing is not identity. Withhold name if biometric/other validated recognition uncertain.
3. **Glasses offline:** show clear disconnected state and provide supported phone-only operations. No fake ongoing recognition.
4. **Camera occluded:** “I can't see clearly right now” on request; never fill in missing positions.
5. **Multiple people speaking:** if speaker identity can't be confidently assigned, avoid claiming who spoke.
6. **Dim environment:** degrade gracefully; optional voice evidence only if permitted and enabled.
7. **Crowded event:** throttle cues aggressively, prioritizing changes and direct user questions.
8. **An enrolled person revokes:** immediate local disable at next sync; if offline, do not claim instant remote deletion until a trusted revocation channel and delivery semantics are implemented. Define offline revocation behavior explicitly and surface it honestly.
9. **Lost phone / changed device:** sensitive local identity data must not silently sync to general backups unless user consent and security model allow it. Explain migration limitations.
10. **User accidentally triggers microphone:** distinct capture indicator, quick stop, no silent recording history.
11. **Glasses device records separately:** Familiar can only control its own app session; respect official hardware capture indicators.
12. **Low battery / thermal throttling:** static Mimo fallback, reduced visual processing, explicit notice only when relevant.
13. **No enrolled contacts:** meaningful onboarding and opt-in flows, not an empty surveillance-like view.
14. **Contact provides no photo:** enrollment contact info may still exist without enabled visual identification; don't pretend face recognition will work.
15. **Opt-in web page is opened by someone else:** short-lived invitation with abuse prevention and verification; user must be able to reject incorrect enrollments.
16. **Consent recording:** if the team ultimately stores a short audio proof of consent, limit collection, define retention/deletion, disclose it to both parties, and obtain legal/policy review. For MVP prefer self-enrollment with recorded structured consent action to avoid recording conversations.

---

# 14. MILESTONE PLAN / WHAT THE HACKATHON SHOULD ACTUALLY BUILD

## Demo-safe MVP (non-negotiable)

- Native SwiftUI experience with a polished Mimo shader and realistic state machine.
- Full onboarding, Privacy explanation, VoiceOver-compatible Home, People, and Invite flows.
- Real QR self-enrollment page with independent consent + revocation process (or clearly marked local demo with no stored biometrics).
- People directory, contact details, and user-initiated native call/text flows.
- Wearable connection status and phone/simulator fallback, with truthful capability indicators.
- Voice commands and spoken mock contact cues **only in an explicit demo/simulator mode** if actual recognition approvals/SDK capabilities are unavailable.
- Privacy guardrails shown prominently in the live demo.

## Stretch goals — only when verified, approved, and safe

- Real on-device opted-in identity recognition with formal policy approval.
- Direction calibration and event debouncing from camera pose/tracking.
- Narrow gesture detection, e.g., a clearly visible wave, with opt-in settings.
- Actual supported Ray-Ban Meta glasses media acquisition and voice/audio routing.
- Fully tested consent revocation synchronization.

## Explicitly out of scope for hackathon

- General stranger identification or profiling.
- Emotion/intent inference.
- Unsolicited outreach or automated messages.
- Full mobility navigation or obstacle avoidance.
- Always-on background recording guarantees.
- Persistent conversation recording and memory summaries.
- Promising immediate revocation while both parties are offline without a verified mechanism.

---

# 15. TWO-MINUTE LIVE DEMO / DIRECTOR'S CUT

**0:00–0:20 — Feeling:** Launch Familiar. Mimo breathes on a clean ivory background. Voiceover: “Being in a room isn't always the same as feeling part of it.”

**0:20–0:45 — Consent:** Tap **Add someone**. A volunteer scans a QR, reviews what will be stored, and explicitly opts in. Familiar announces: “Maya chose to connect.” Explain revocation in one sentence.

**0:45–1:15 — Social moment:** Put the glasses or camera into the explicitly marked, pre-approved live mode **or demo simulation**. Cue: “Maya, two o'clock.” The user looks toward Maya and says hi first. Never disguise simulated recognition as real device capture.

**1:15–1:35 — Control:** Ask “Who's here?” Voice gives a brief roll call. Another person is simply “someone,” never identified. Tap Pause; Mimo settles and says “Awareness paused.”

**1:35–2:00 — Mission:** “Familiar doesn't make conversations for you. It gives you enough context to start them yourself.” Close on the large orb and tagline **“Be part of the moment.”**

**Key judge takeaway:** An original, living AI companion with hardware ambition; a concrete social accessibility problem; consent architected into the experience; honest capability boundaries.

---

# 16. DEFINITION OF DONE / QUALITY BAR

### Visual excellence
- [ ] Mimo looks like a **dimensional living character**, not a flat gradient circle.
- [ ] Shader motions have elegant easing, delicate specular highlights, and low distraction.
- [ ] Face feels instantly recognizable, cute but not childish.
- [ ] Screens have the visual refinement of the user's editorial, pill-based reference.
- [ ] Content hierarchy remains intelligible in 1-second glance and without a glance at all.
- [ ] Light, dark, Reduce Motion, Reduce Transparency, and high-contrast variants exist.

### Interaction and accessibility
- [ ] All major flows complete with VoiceOver and large text.
- [ ] 44pt+ targets, clear button names, no hidden solely visual interactions.
- [ ] Voice is opt-in, stoppable, and concise.
- [ ] Pause is available from Home and via a fast supported command.
- [ ] Device unavailability is handled honestly.

### Product trust
- [ ] No unidentified person's data saved.
- [ ] Self-enrollment requires informed explicit consent.
- [ ] Clear revocation and removal paths.
- [ ] No false claims about on-device processing or cloud transfer.
- [ ] No mood inference, stranger profiling, or unsafe mobility claims.
- [ ] Recognition capability only enabled with validated technical, platform, and policy compliance.

### Engineering
- [ ] Avatar shader degrades gracefully and doesn't harm battery unnecessarily.
- [ ] State transitions testable in deterministic simulation.
- [ ] Voice cues are throttled and do not endlessly repeat.
- [ ] Data flows have explicit trust boundaries and deletion tests.
- [ ] Native SwiftUI architecture, no web-wrapper masquerading as an app.

---

# 17. EXECUTION PROMPT FOR A SWIFTUI BUILD AGENT

> Build a premium, fully native iPhone SwiftUI application called **Familiar** using this design specification as authoritative. The product is a consent-first social-awareness companion for people across the full spectrum of visual impairment, designed for optional Ray-Ban Meta glasses integration. Its visual centerpiece is **Mimo**, an original cute floating glassy orb with softly animated teal/lilac/sky-blue/peach liquid gradients, crisp tiny expressive eyes, minimal mouth, natural blinks, and distinct listening/thinking/responding/paused states. Use SwiftUI and Metal (with reduced-motion fallback), SF typography, airy ivory canvases, polished white cards and floating pill navigation. Implement complete screens for Welcome, privacy onboarding, accessibility preferences, device connection, Home, Listening, Roll Call, People, contact detail, independent QR enrollment, consent status, optional Moments, and Settings. Build an original design system, VoiceOver-first semantics, Dynamic Type support, genuine pause control, structured mock awareness events, and clear distinction between simulated features and live capabilities. Treat user-provided Familiar product guards as non-negotiable. Do not claim real facial recognition, background glasses streaming, automatic device pairing, instant deletion, or approvals unless validated and implemented. The result should feel like a shipped high-end consumer application, not a hackathon dashboard or generic AI chat client.

---

# 18. HANDOFF SUMMARY

**Name:** Familiar.  
**Mascot:** Mimo — an original, living, liquid-light orb with a cute minimal face.  
**Core interaction:** Know when *consenting* people are present, make first contact, and reconnect later.  
**Primary interface:** Speech, short contextual cues, user-led control.  
**Visual signature:** Warm ivory, restrained typography, dimensional iridescent Mimo shader, spacious cards, floating nav.  
**Hardware:** Native iOS first; Ray-Ban Meta glasses as optional, verified partner interface.  
**Trust signature:** Known people only, consent-first, local-sensitive-data architecture, uncertainty over guesses, immediate user control.  
**Product mission:** **Be part of the moment.**

---

# 19. DESIGN REFINEMENT V1.1 — FULL VISION SPECTRUM + DISTINCTIVE MUSE-INSPIRED COMPANION

**Decision:** Familiar is for people across the spectrum of vision loss: people who are totally blind, people with low vision, central or peripheral field loss, fluctuating vision, glare sensitivity, contrast sensitivity differences, and people who switch between vision and nonvisual interaction depending on circumstances. Never equate all visual impairment with complete blindness. Do not infer clinical diagnoses from settings.

## 19.1 Reframed product promise

- **Public promise:** “Recognize the people who chose to be familiar — in the way that works for you.”
- **Emotional promise:** “Feel included without having to ask who just walked into the room.”
- **Core product job:** Social presence and recognition of *consenting known people*, not navigation, stranger analysis, or surveillance.
- **Experience:** Visual when useful, spoken when useful, haptic when useful, and ideally hands-free through glasses; every meaningful action works without relying on only one modality.
- **Visual direction:** Muse-adjacent friendliness and luminous energy, blended with the lovable simplicity of a tiny robot mascot, but **original silhouette, original face, original motion vocabulary, and no copied logo/character**.

### Vision modes: preferences, not labels or separate apps

Onboarding asks: **“How would you like Familiar to communicate?”** Choose any combination and adjust later; do not ask users to categorize themselves as blind/partially sighted.

| Mode preset | Default adaptations | What must stay possible |
|---|---|---|
| **Audio first** | Spoken social cues, short earcons, screenreader-friendly control hierarchy, visual UI still present | Full setup, consent management, device state, and removal of contacts with VoiceOver and without sight |
| **Enhanced vision** | 22–26pt primary type where appropriate, powerful contrast, enlarged hit areas, explicit labels, optional magnification-friendly layout | Control whole experience without squinting, horizontal clipping, or color-only information |
| **Balanced** | Elegant visual design plus optional concise voice cues | Seamless visual/audio handoff without duplicate announcements |
| **Quiet visual** | Large text event cards and optional haptic cues, muted spoken prompts | Recognition and consent states understood without sound |
| **Custom** | Independently choose scale, text weight, contrast, motion, labels, spoken detail, direction format, haptic intensity and sounds | Saved and reflected instantly throughout the application |

These are *starting presets* only. System settings (Dynamic Type, VoiceOver, Bold Text, Increase Contrast, Reduce Transparency, Reduce Motion, Differentiate Without Color) must take precedence unless the user consciously overrides a compatible in-app preference. Respect zoom, display accommodations, and dark mode. Do not silently reset preferences after pairing glasses.

## 19.2 Two equally beautiful interface layers

**Layer A — editorial consumer UI:** The light, luminous layout supplied in the reference: warm off-white, very spacious, floating visual companion, huge visual confidence, refined cards, confident type, smooth but restrained motion. This is the app's aspirational default, not an inaccessible “standard mode.”

**Layer B — accessible precision UI:** Same architecture and personality, but adapts to larger text, fewer columns, simpler backgrounds, stronger dividers, solid surfaces, visible focus, textual states, and deliberate grouping. It is **not** an ugly or stripped-down backup. Personalize the look without changing the underlying navigation structure.

On small phones and large Dynamic Type, cards become single-column, bottom navigation becomes legible list or accessible tab UI, summary content never relies on fixed-height clipping. Under VoiceOver, Mimo is one meaningful element, e.g. “Familiar assistant, listening,” not dozens of separately focusable decorative layers.

## 19.3 MIMO V2 — character/art direction (must feel alive)

**Internal codename:** *Mimo, the little lightkeeper.* Friendly, warm, mischievous in micro-moments, trustworthy when uncertain. Imagine a soft plump pebble of refractive light that happens to have a tiny face. Not a chatbot emoji, not a flat blue circle, not an exact copy of Grok’s character, and not Meta’s Muse identity artwork. Cute ≠ childish.

**Silhouette:** Slightly imperfect rounded blob (not mathematically circular), roughly 1:1 aspect ratio, with a very subtle flattened base; squashes by 2–4% on acknowledgments, stretches by 2% when alerting, returns on spring. On the main page it occupies about 42–58% of available screen width depending on screen size, never blocking information.

**Body:** Multi-layer living shader: pastel cyan/azure core, electric cornflower caustics, soft periwinkle/mauve rim, tiny pearlescent mint highlights, peach flash only as a sparing warmth accent. Chromatic depth comes from overlapping procedural fields; it must **not** look like a static blurred gradient. Aim for a translucent, polished, soft-gel form that exhibits a gentle inner current. Avoid intense strobing, thick neon outlines, rainbow overload, “liquid metal” chrome everywhere, or glossy plastic toy vibes.

**Face:** Two tiny dark ink eyes, slightly asymmetric natural spacing; small curved mouth appears during greetings/speaking and occasionally smiles. Tiny eyebrow curves only when conveying a meaningful conversational state. Blink at irregular but natural intervals. The face must remain pinned sharply above moving body shader; never let the shader blur eyes or reduce their contrast. Body lighting can move, face must be easy to recognize.

**Affective palette / controlled state machine:**

| State | Motion | Face | Accessible equivalent |
|---|---|---|---|
| Idle | Slow breathing (~5–7s), low-amplitude internal drift | Neutral eyes, occasional blink | “Ready” status in text and accessibility value |
| Listening | One gentle inward compression, soft iris-like light region around center | Eyes attentive, tiny eye shift | Text “Listening”; optional start chime/haptic |
| Thinking | 2–3 slow nested color currents, subtle rotation of internal light | Eyes glance up or side, not rapid blinking | “Processing”; non-looping announcement if delay matters |
| Speaking | Voice-amplitude-fed soft surface wave, not frame-by-frame mouth lip sync | Small mouth opens minimally | Spoken content and synchronized live text |
| Recognized event | One warm ripple + barely perceptible happy bob | Small friendly smile | Short spoken cue, text event, optional haptic |
| Uncertain | Movement slows and color saturation decreases slightly | Neutral expression | Explicit “Not sure” label; no inferred identity |
| Muted / privacy pause | Frozen, unanimated soft gray-blue texture | Eyes relaxed/closed | Clearly labeled paused state, persistent controls |
| No device | Gentle quiet glow, no simulated camera activity | Neutral | “Glasses disconnected” status with troubleshoot button |

**Novel signature move:** *Lumen ripple.* When Familiar receives an allowed cue, a localized band of light ripples **through** the orb interior and resolves into a tiny smile — a delightful acknowledgment without implying extra knowledge. For direction cues, use a brief localized sheen on one side of the orb *only as redundant illustration*, never as the sole directional signal. Put a large text arrow or spoken clock direction beside it.

**Motion constraints:** Preserve contrast and reduce flashes. Under Reduce Motion, Mimo becomes a high-quality static or subtly crossfading illustration; no continuous translation, rotation, or parallax. On Low Power Mode / thermally constrained states throttle shaders and adopt a static fallback. Mimo is decorative unless it is the explicitly selected voice trigger; provide a separate persistent, appropriately labeled voice button.

## 19.4 Native shader implementation blueprint — iPhone-first, NOT web copy/paste

- Use **SwiftUI** for view hierarchy, VoiceOver semantics, Dynamic Type, focus, buttons, consent sheets, and onboarding.
- Use **Metal Shading Language** and `ShaderLibrary` with `colorEffect`, `layerEffect`, and where appropriate `distortionEffect` for the shader; alternatively a `MTKView` rendered into a controlled SwiftUI wrapper when texture feedback or more complex passes are genuinely needed.
- The shader receives explicit `time`, `size`, `state`, `amplitude`, `reduceMotion`, and color parameters. Make face geometry a separate crisp SwiftUI Canvas/path overlay or scalable asset.
- Surface math: signed-distance rounded silhouette, two or three low-frequency animated warped noise fields, refraction-inspired internal gradients, internal specular lobes, restrained Fresnel-like rim and soft contact shadow. Add sparing micro-particles only if performant.
- Preferred aesthetic: spectral gel + velvet diffuse shading + quiet “alive” liquidity. Use fixed limited color stops; shape with smoothstep, not a fast random flicker.
- Drive motion from a single app-owned animation clock, not independent unbounded timelines. Use voice amplitude only when microphone permission is granted and audio is actually active. No pretend listening/recording visual.
- Cache pipeline states, avoid CPU texture rebuilds per frame, cap fill area and shader passes, profile frame pacing and battery impact on a real iPhone. Provide a clean static image fallback for devices/OS combinations without the needed shader API.

**Design tokens (starting points, validate visually):**

```
App.canvas          #F8F7F4   // ivory, dark mode uses ink canvas
App.surface         #FFFFFF
Ink.primary         #172128
Ink.secondary       #465560
Accent.sky          #79C9F7
Accent.cornflower   #5A95EA
Accent.lilac        #B5A6FF
Accent.mint         #A6E9D9
Accent.peach        #F5C9AC
Status.success      #127353   // only with text/icon
Status.warning      #925A12   // only with text/icon
Surface.corner      26pt
Control.minimumHit  44x44pt; target 52x52pt for primary actions
```

The palette above is brand art direction, **not proof of sufficient accessible contrast**. Validate all text/control combinations. The pale gradient must never serve as text background when it fails contrast. In enhanced-vision mode default to opaque neutral controls and near-black text; test non-text boundaries, disabled states, and focus indicators.

### Mini shader pseudocode specification (not production MSL)

```
uv = normalizedCoordinates(position, size)
silhouette = roundedBlobSDF(uv, breathingAndStateDisplacement)
flowA = fbm(warp(uv, time * 0.05, scale=2.2))
flowB = fbm(warp(rotate(uv, 0.3), time * -0.035, scale=3.7))
caustic = smoothstep(0.54, 0.76, flowA - 0.35*flowB)
bodyColor = mix(sky, lilac, flowA) + mintAccent(caustic)
rim = restrainedFresnel(silhouette)
rgba = composite(bodyColor, diffusedHighlights, rim, alphaFromSDF)
// FACE drawn AFTER shader in separate crisp accessible overlay
```

### Render acceptance criteria

- Idle feels truly alive after 30 seconds but is calm enough to ignore.
- 30-second screen recording shows no repetitive obvious loop seams.
- Facial marks remain sharp against darkest/lightest moments of the gel.
- Voice response has synchronized but non-jittery amplitude envelope.
- Static fallback looks intentional and still recognizably “Mimo.”
- In reduced motion and VoiceOver, full functional parity holds without relying on observing animation.

## 19.5 Inspiration-to-native translation; vetted usefulness

These references are **inspiration/discovery**, not Swift packages to drop directly into the iOS app. Extract design principles and recreate natively, with original artwork and licensing checks.

| Resource | Use it for | Native Familiar translation | Priority |
|---|---|---|---|
| https://inspora.design | Creative compositions, editorial spacing, soft premium color mood | Home hero, onboarding story panels, screenshots | High |
| https://designeer.xyz | Shared collection URL supplied by team; verify current availability | Component patterns, interaction benchmarks, animation references | Medium |
| https://designeer.org | Currently discoverable indexed design/tools directory; not assumed same publisher as .xyz | Animation & shader tools to research, motion detail | Medium |
| https://scrolltide.co | Complex procedural motion/3D interaction inspiration | Orb material language and curated transitions, **not** scrolljacking | High for exploration |
| https://backgrounds.supply | Background textures, soft gradients, atmospherics | Calm non-interactive hero backgrounds; ensure text contrast | Medium |
| https://fontshare.com | Free-to-use font exploration, subject to individual licenses | Marketing or brand display; iOS UI defaults to SF for legibility | Medium |
| https://cta.gallery | Primary action hierarchy and button composition | “Start listening,” “Who's here?”, “Pause”, “Invite someone” | High |
| https://footer.design | Web information hierarchy references | Only inspiration for a possible launch site, not iOS footer | Low |
| https://reelfolio.io | Presentation and polished portfolio storytelling | Launch video, project showcase, demo narrative | Low |
| https://libraries.dev | Thinking orb, AI avatar, voice-responsive effects and references | Prototype shader visuals; reimplement native; check SwiftUI-supported variants | High |

**Specific research finding:** libraries.dev advertises native SwiftUI versions for Beam and Orb but describes many of its primary effects as React libraries. Do not assume its React npm packages work in SwiftUI. Check the actual API, iOS version requirements, licensing and runtime performance before incorporating anything. Similarly, a visually impressive web scroll animation usually does **not** belong inside an accessible, voice-first native phone app.

**Inspiration filter:** save only references that answer one of: (a) expressive but legible AI character, (b) tactile/clear UI affordances, (c) hero composition that survives Dynamic Type, (d) motion that can be reduced, or (e) honest device/permission state. Reject gratuitous visual effects.

## 19.6 Enhanced-vision UX refinements by screen

### Home

- A visually beautiful Mimo centered above a direct, large, high-contrast summary: **“Ready to help you connect.”**
- Prominent single primary button, “Who's here?”; separate one-tap **Pause all cues** control with text label.
- One plain-glance device pill: “Glasses connected” or “Using iPhone” — do not use a mint dot alone.
- Recent recognized-person event (if true, authorized, and current) shown as high-contrast card with name, approximate direction, optional Call/Text.
- Screenreader first element announces only the current useful summary, not every ornament. Gestures never required.

### Live awareness

- Responsive content hierarchy: **person name > direction > action**.
- At enhanced text sizes, collapse into stacked rows; never force side-by-side tiny labels.
- Optional scene snapshot overlay with object highlighting can help residual-vision users, but it must never expose non-consenting strangers' identities or imply face identification approval.
- Show explicit status: **“Known person, confirmed”**, **“Unknown person”**, **“Unable to confirm”** (only if supported by actual pipeline).

### People

- Adjustable large list tiles, persistent search label, clearly separated “Opted in” vs “Pending permission.” No ambiguous colored badge-only statuses.
- Optional monogram/photo only if voluntarily supplied and permitted. High contrast name, relationship context, clear **Call**, **Text**, **Remove** actions.
- Deleting or revoking consent must always have an accessible path independent of gesture shortcuts.

### Enrollment and trust

- The other person independently completes enrollment on their own phone. The blind or low-vision user must never need to verify someone's face by looking at the screen.
- Explain in plain language exactly what is collected, where stored, how to revoke. Separate opt-in for optional face/voice data if needed.
- Don't record or keep consent audio by default without a clear legal, privacy and threat-model review; the original concept proposes keeping a short clip, so implement only after explicitly reconciling consent evidence, retention, deletion and applicable law.
- Use a *reversible, prominent* test consent interaction in the demo. No hidden capture.

### Settings

- Top-level controls: Vision & display; Audio & speech; Haptics; Mimo appearance; Glasses/device; People & permission; Privacy & data.
- “Preview my settings” lets users test a cue in large text, speech, and haptics **without enabling camera or microphone**.
- Offer optional Mimo visibility settings (full, compact, hidden) while preserving voice functionality.

## 19.7 Accessibility test matrix — executable product QA

| Scenario | Verification |
|---|---|
| VoiceOver on, screen dark | Complete initial setup using spoken hints and logical rotor navigation; manage known contacts and pause cues |
| Largest Dynamic Type and Bold Text | No clipped names/buttons; cards reflow; no horizontal scrolling for core controls |
| Increase Contrast + Differentiate Without Color | Status, action, and person identity readable with text/icons, not hue |
| Reduce Motion + Reduce Transparency | Static Mimo, no essential visual cue lost, translucent sheets become opaque |
| Dark mode + Smart Invert | Text and primary controls stay readable; Mimo doesn't create blinding contrast |
| 200%/300% magnification use | All primary actions still discoverable, no layout requiring zoom-out to finish a critical flow |
| Partial central vision / peripheral vision differences | Information isn't confined to small central badges or screen corners; configurable simple layout |
| Hearing limitations in combination with low vision | All speech cues available as readable large text and optional vibration |
| Glasses disconnected / permission denied | Honest state, fully accessible troubleshooting, optional iPhone mode |
| Camera uncertain / false identity risk | No invented names; uncertainty explicit in visual and audio channel |
| No consenting people | Useful empty state and opt-in path; no profiling of strangers |
| Offline / privacy mode | Accurate functionality disclosure; never imply server-free if any active cloud request exists |

Recruit participants with a range of vision profiles and preferred assistive tools. Provide session compensation where possible. Avoid treating blindfolded sighted testers as substitutes. Test usability and dignity, not only task completion.

## 19.8 Native implementation artifact plan

Recommended SwiftUI files for this revision:

```
DesignSystem/FamiliarPalette.swift
DesignSystem/FamiliarTypeScale.swift
DesignSystem/AdaptiveSurface.swift
DesignSystem/AccessibleActionButton.swift
DesignSystem/GlassStatusBadge.swift
Avatar/MimoShader.metal
Avatar/MimoRenderer.swift
Avatar/MimoFace.swift
Avatar/MimoStateMachine.swift
Avatar/MimoReducedMotionFallback.swift
Preferences/CommunicationMode.swift
Preferences/VisionDisplayPreferences.swift
Preferences/AccessiblePreview.swift
Screens/Home/HomeHeroView.swift
Screens/Home/RecognitionSummaryCard.swift
Screens/Live/LiveAwarenessView.swift
Screens/People/OptedInPersonRow.swift
Screens/People/EnrollContactView.swift
Screens/Settings/AccessibilitySettingsView.swift

Tests/VoiceOverFocusTests.swift
Tests/DynamicTypeLayoutTests.swift
Tests/ConsentAndRevocationTests.swift
Tests/AvatarStateTests.swift
```

**Dependency discipline:** Start with Apple frameworks: SwiftUI, Metal, AVFoundation, CoreHaptics (where supported), Accessibility, Combine/Observation, and native networking when necessary. Add third-party packages only when they materially solve a hard problem; document maintenance, license, privacy, and size. Avoid embedding a WebView merely to import React effects.

## 19.9 Final direction for designer and coding agent

> Update Familiar, a truly native SwiftUI iPhone app for **people across the full spectrum of visual impairment**, not only users who are totally blind. Its mission is socially inclusive awareness of people who have explicitly opted in, delivered through the user's preferred mix of visual, voice, and tactile cues. Create a world-class, airy and warm, consumer-quality visual design based on the supplied minimal meditation reference. The visual icon is Mimo: an original, lovable little light-being with clean tiny expressive face floating over a volumetric, Muse-inspired, living cyan/blue/lilac/mint gel shader. The body must have gorgeous slow internal currents, optical depth, pearlescent rim lighting and subtle state-aware movement, built with performant **native Metal/SwiftUI**, and not a generic static gradient orb or a copied corporate mascot. Use the cited inspiration galleries as visual research, and libraries.dev for studying effects and native-compatible references only. Deliver all key app flows with adaptive large typography, robust high contrast, VoiceOver, Reduce Motion, clear consent and device states, and accessibility across varying residual-vision needs. Mimo should add delight without blocking task completion. Demonstrate both the stunning default visual presentation and a beautiful enhanced-vision mode. Never present unreleased glasses recognition as approved or working, and never identify nonconsenting people.

### Source notes (reviewed October 2026)

- Apple accessible appearance: https://developer.apple.com/documentation/swiftui/accessible-appearance
- Apple accessibility fundamentals: https://developer.apple.com/documentation/SwiftUI/Accessibility-fundamentals
- Apple graphics/shader API: https://developer.apple.com/documentation/swiftui/view-graphics-and-rendering
- libraries.dev packages and native support statements: https://libraries.dev/
- Design references provided by team are inspiration sources, not technical API documentation.


---

# 20. VERSION 1.2 — THE SOCIAL INDEPENDENCE EDITION

**Design directive (supersedes earlier narrative choices when they conflict):** Familiar is a premium native iOS social-awareness companion **specifically for people who are blind, have low vision, or have other visual impairments**. It is not a generalized AI social app for sighted audiences. The supporting participant experience exists only so friends, relatives, colleagues, and new acquaintances can *voluntarily* join Familiar's consent-based contact network. The ultimate value is **social agency**: the choice to initiate, participate, and reconnect on one's own terms.

## 20.1 The defining insight and pitch

> **“The hardest part of navigating a room isn't always finding the door. Sometimes, it's finding your place in the conversation.”**

Familiar doesn't simply identify familiar faces; it makes the ordinarily unspoken layer of social life accessible. In a room, sighted people may notice a coworker approaching, a friend waving, a colleague leaving mid-conversation, or someone turning toward them to speak. These cues are not trivia. They shape who gets to say hello first, who feels included, and which professional and personal relationships develop. Familiar offers **selective, consent-based observations**, translated into personalized speech, spatial sound, haptics, and enhanced-vision visuals.

**Public-facing one-line pitch:** “Familiar gives people with visual impairments a sixth sense for human connection, making everyday social cues accessible through consent-first AI glasses and a deeply personal companion.”

**Hero headline:** **Feel at home in every room.**

**Hero subhead:** **Know when someone you know is near, approaching, waving, or leaving — quietly, on your terms.**

**Closing line for demo/story:** “We're not replacing human connection with artificial intelligence. We're using AI to make human connection more accessible.”

**Tone guardrail:** Never position disability as tragedy, never guarantee independence in all settings, never claim the app reads minds/emotions, and never suggest that the user cannot socialize without the app. Product copy is invitational, precise, empowering, and respectful.

## 20.2 The single signature moment

Build every screen, animation, and presentation around one scene:

1. A participant who is blind or has low vision arrives at a gathering, glasses connected and Familiar in **Normal** mode.
2. An **already enrolled, consenting** friend approaches from camera-right.
3. The on-device perception layer observes a sufficiently confident match; the event engine confirms approach across multiple observations.
4. Mimo subtly lights up (visually optional); the user's audio output says: **“Maya, approaching from your right.”**
5. The user chooses to turn and greet Maya **before** Maya says anything.
6. The friend smiles and they start an ordinary conversation. Familiar falls silent.

**Emotional punchline:** *It wasn't about recognizing a face. It was about getting the chance to say hello first.*

**Technical integrity:** If identity confidence is insufficient, use “Someone is approaching” or remain silent based on settings. Do not fabricate specific distance, recognition certainty, or gesture direction. Keep the demo clearly distinguished from any scripted/mock data.

## 20.3 Five outcome pillars

| Pillar | Human value | In-product capability | Acceptance evidence |
|---|---|---|---|
| Recognition with dignity | Greet someone first | Approved on-device, opted-in known-person recognition; on-demand roll call | Correct identification vs abstention on test scenarios |
| Presence and continuity | Know who joined or left | Arrival/departure cues, conversation-presence event state | No duplicate announcements during one arrival |
| Shared attention | Catch a visible invitation | Opt-in, observable wave/nod cue; never interpret mood/intent | Gesture cue only when supported and sufficiently certain |
| Relationships beyond the room | Reconnect later | Consent-first contact enrollment and opt-in contact detail | New contact can call/text through user confirmation |
| Self-directed control | Avoid overwhelm or embarrassment | Quiet/Normal/Chatty modes, immediate mute, custom channels, audio-first and high-vision modes | Fully operable eyes-free and at maximum supported Dynamic Type |

## 20.4 Native app information architecture, revised

### Primary bottom navigation (four destinations)

**Today** — contextual home and Mimo stage; states: Glasses Connected / Phone Demo Mode / Offline. A large, accessible primary action **“What's around me?”** invokes an on-demand snapshot, never constant narration. Secondary row: **People nearby**, **Social cues**, **Privacy**.

**Room** — *live social awareness* shows a sparse, time-sensitive representation of consenting known people only. For residual-vision users: optional high-contrast radar with large directional segments, labels, and nearby/medium/far buckets. For VoiceOver: logically ordered names, directional phrases, action buttons, and a short spoken summary. Unknown people receive generic counts only where that detection is appropriate and reliable. Avoid faux precise maps when camera geometry does not support them.

**People** — enrolled contacts, consent status, familiar notes (where/when met, with user confirmation), permission expiry if applicable, one-tap revocation, Call/Text actions. No social feeds, public profiles, or contact discovery via covert surveillance.

**You** — profile, accessibility and cue preferences, glasses/device connection, permissions, consent receipts, data controls, export/delete, accessibility help, and learning mode. Settings must be fast to reach with both VoiceOver and large type.

### Global persistent interaction

- Mimo is the consistent companion **not a giant floating obstruction**: full stage on Today, compact presence at top of Room, unobtrusive voice response indicator elsewhere.
- A clearly labeled **Mute cues** control must always be accessible via a fixed action or supported hardware gesture; do not put mute behind a decorative avatar interaction.
- Priority cue channels: `voice`, `spatial_voice_if_supported`, `haptic`, `large_text`, `high_contrast_graphics`.
- A visible and spoken **“Camera active”** indication must reflect actual device state. Respect the glasses' hardware recording indicators.

## 20.5 Screen-by-screen v1.2 redesign

### 01 — Welcome / First launch

**Hero:** Massive, soft pearlescent Mimo floating in an airy field of warm cream with a gentle cyan-violet glow. Beneath it: **“Hello. I'm Mimo.”** and **“I'm here to make the little social moments easier to catch.”** Primary CTA **“Get started”**. Secondary **“Explore a demo”**, clearly simulated. “Made for blind and low-vision people” is explicit, not hidden deep in settings.

### 02 — Personalized access, not a diagnosis survey

Ask **“How would you like Familiar to communicate?”** Offer Audio First, Enhanced Vision, Balanced, Quiet Visual, and Build My Own. Each preset changes defaults, not the available feature set. Let users test a cue live via the speaker and read the same cue visually. Support Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast, Differentiate Without Color, Bold Text, and switch/voice control.

### 03 — Privacy promise / glass pairing

Short, understandable sequence: **“Only recognize people who say yes.”** **“Your enrolled recognition information stays on your phone.”** **“You control when Familiar speaks.”** Then **Connect glasses** / **Continue with phone demo**. Do not claim a pairing succeeded until the actual SDK reports connected. Make permissions incremental and explain camera/microphone use before system prompts.

### 04 — Today / the emotional hero screen

Mimo is the visual focus. Warm, organic light field with subtle motion. **“You're all set.”** / **“Ready when you are.”** Main CTA: **“Who's here?”** Under it, a status chip “Glasses connected” or “Demo mode,” plus a smaller quiet statement: **“We'll speak when something matters.”** Show last verified event only if consented and retained by the user; never imply the app retains complete conversations.

### 05 — Room / live awareness

Top banner: **“In the room”** and current cue level. Visually accessible segmented radar optional, surrounded by large straightforward list cards: “Maya · right · nearby,” “Sam · left · farther away.” Every card is one VoiceOver element, can announce its contents, and offers **Call / Details / Silence this person** where appropriate. Dynamic Type switches radar to list-only before crowding. A subtle “Last updated just now” indicator must reflect actual observed timestamps; when camera unavailable, say **“Room awareness paused.”**

### 06 — Social cue detail

Focus on one **observable** event: “Maya waved from your left.” Include **“Heard at 2:41 PM”** only if temporary event history is on. Quick controls: **Repeat cue**, **Silence similar cues**, **Review cue settings**. No “Maya is happy/excited,” no inferential mood scores, no “they want to talk to you” as a fact.

### 07 — People / relationships, not a contact database

Rich but highly legible rows: large name, optionally user-chosen pronunciation, opt-in status, last user-confirmed context (“Met at the engineering fair”). People have clear consent controls. “Add someone” starts a **consenting enrollment** flow. Avoid face thumbnails as the only identity signal. Contact sync requires explicit user approval and OS-granted permission.

### 08 — Invite to be remembered

A beautifully simple share sheet presents an NFC tag or QR/short link alternative. The invited person opens a web page on *their own device*, sees why their photo and optionally contact details are requested, chooses to enroll, and can revoke later. Explicit opt-in is required; no pre-checked boxes. Accessibility and plain-language copy apply to the guest page too. No forced app download. Treat spoken-consent enrollment as a future capability until identity, speaker, retention, and policy checks are solved.

### 09 — Your privacy dashboard

Primary card **“Your people. Your control.”** Show counts of active consents, paused recognition, and pending invitations. Every enrolled contact can be removed; ensure removal invalidates local recognition data. Describe actual backend behavior precisely; do not promise instant deletion across offline devices without an operational mechanism. Provide **Delete all known people**, with a confirmation that doesn't rely on color alone.

### 10 — Modes and sensory output

Top-level **Quiet / Normal / Chatty** with contextual explanations. Separate toggles for Approach, Leave, First speaker, Wave, Nod, and “Who's here?” (on-demand). A live preview plays a real local sample cue. Adjustable speech rate, volume, preferred output, left/right spatial audio if available, vibration pattern if available, contrast, text size, and motion preferences.

### 11 — Demo simulator

A fully offline, clearly labeled scenario player with simulated consenting characters: Maya approaches; Sam leaves; Maya waves; unknown person passes but is not named. It renders equivalent voice, transcript, optional visuals, and haptic placeholders. It must not pass staged predictions off as functioning live recognition. This is a fallback for judging when hardware/API permissions are unavailable.

## 20.6 Mimo 3.0 — playful, original, instantly recognizable

**Personality:** a small, translucent, almost-liquid creature of light. Muse-inspired warmth and fluidity, Grok-like expressive simplicity, but **not** a copy of either company's avatar, silhouette, marks, or animation assets.

**Form:** softly asymmetric 3D orb, slightly elongated at rest, with barely perceptible breathing. Its volume is made from **two intersecting slow fluid color fields** instead of one flat radial gradient. An opalescent skin catches an upper-left key light; a thin specular rim separates it from the background. Its two tiny dark eyes float on the forward-facing surface; the face remains discernible under all states. An understated curved mouth appears for welcome/celebration only. Minimal floating shadow anchors it.

**Material:** translucent milky shell + internal cyan/seafoam/blue/lilac pigment streams + pearlescent additive highlight + fine low-amplitude noise; no excessive bloom, no hard chrome, no rapid rainbow strobing, no uncanny human face. Favor a carefully art-directed 60 fps Metal render with 30 fps energy-save fallback.

**Motion language:** Motion is communication, not decoration. Idle = slow breathing (4–7 second cycle); listening = subtle squash + focused glow; thinking = gentle pigment circulation; talking = phoneme/energy-reactive micro-bounce; social cue = one concise left/right shimmer; recognition uncertainty = stillness rather than an exaggerated “confused” animation; muted = settled, reduced luminosity, no attention-grabbing pulses. Respect system Reduce Motion by stopping all spatial deformation and presenting a static high-contrast face + state label.

**Shader implementation requirements:** Native Metal fragment shader, SwiftUI wrapper via `MTKView` or a modern supported shader integration; exposed uniforms `time`, `resolution`, `state`, `audioEnergy`, `direction`, `reduceMotion`, `contrastMode`, `thermalQuality`. Generate the soft shell mask using smoothed signed-distance / elliptical field, animate a bounded field warp with low-frequency noise, mix pigments in linear-light where appropriate, add clipped fresnel-like rim lighting, and compose eyes/mouth on a separate crisp overlay layer for stable legibility. Avoid relying on shader output for screen-reader meaning.

**Avatar state labels:** Every state must have a plain text counterpart: “Ready,” “Listening,” “Thinking,” “Speaking,” “Muted,” “Glasses disconnected,” “Cue available.” Announcements should be rate-limited to avoid speech spam and not compete with a conversation.

### Palette tokens — warm yet credible

| Token | Light | High-contrast alternative | Role |
|---|---|---|---|
| Canvas | `#F7F8F5` | `#FFFFFF` | Primary background |
| Ink | `#172236` | `#07111F` | Body text |
| Secondary ink | `#576477` | `#26364B` | Supporting content |
| Ocean | `#2779E7` | `#0053B8` | Active/accent controls |
| Lilac | `#A08EF4` | `#6741B8` | Companion pigment |
| Mint | `#75D9CF` | `#00776D` | Companion pigment |
| Surface | `#FFFFFF` | `#FFFFFF` with ink border | Cards |
| Focus | `#1B64D8` | `#003B8E` | Keyboard/switch focus |

Meet **WCAG AA 4.5:1 normal text, 3:1 large text and non-text controls** as a minimum; validate actual composite backgrounds and scrims, not token values alone. High-contrast mode replaces translucent cards with opaque solids, stronger borders, and no critical gradient-dependent labels. Support light and dark appearance rather than assuming all low-vision users prefer the same brightness.

### Native typography

Prefer SF Pro / SF Rounded and Dynamic Type as implementation defaults. Brand display text can use a licensed font, but readable body copy should prioritize Apple's text styles, monospaced digits only for timestamps/technical status, sensible line lengths, and full content reflow at accessibility sizes. Do not ship web fonts merely because they appear in font-inspiration galleries.

## 20.7 Motion storyboard for a 20-second brand sequence

- **0–3s:** Cream canvas; small Mimo peeks into view with two curious eyes; title “Familiar.” appears.
- **3–6s:** “Feel at home in every room.” Mimo turns gently toward incoming voice energy, and a “Glasses connected” label becomes legible.
- **6–10s:** Transition to Room; two broad direction cards appear: Maya right, Sam left. Mimo stays small and doesn't obscure text.
- **10–14s:** A single soft side shimmer as Maya approaches, then spoken cue “Maya, approaching from your right.”
- **14–17s:** The interface falls quiet and gives visual space to the human interaction.
- **17–20s:** Closing type: “The chance to say hello first.” / Familiar logo.

This is an optional promotional/demo sequence, not an onboarding interruption. Include a skip button, respect Reduce Motion, and never autoplay sound unexpectedly in the app.

## 20.8 Business and social impact — product language, not invented evidence

**Primary user:** a blind or low-vision adult who wants more access to social cues at school, work, gatherings, conferences, family events, or community spaces. Visual impairment is a diverse spectrum; test with people using screen readers, magnification, high contrast, residual vision, or combinations of assistive techniques.

**Secondary participant:** someone who *chooses* to be recognized. Their experience must take under 30 seconds when feasible, clearly communicate what data is stored and why, and make leaving just as easy as joining.

**Possible value channels for discovery:** direct-to-consumer assistive subscription, institutional accessibility programs, universities, workplace accommodations, rehabilitation partners, and event accessibility programs. These are hypotheses requiring user research; do not invent market size, clinical outcomes, demand, or pricing proof. Do not make social participation contingent on paying for core privacy/accessibility controls.

**Potential success metrics:** consenting-person enrollment completion and removal, abstention rate on ambiguous identity, correctly identified first-arrival events, cues-per-hour (user-adjusted), perceived interruption burden, independent greeting opportunities, user-reported comfort/confidence, accessibility task completion, privacy comprehension. Partner with blind/low-vision participants to choose *which* metrics matter; avoid framing increased social interaction as a universal obligation.

## 20.9 Technical architecture: privacy/policy-first

```text
Supported glasses (camera/audio)            Native iPhone app (SwiftUI)
               |                                       |
        Wearables SDK  ---------------->  Local frame / audio pipeline
                                                    |
                              Consent + recognition policy gate
                                                    |
                               Local perception (approved capability)
                                                    |
                             Spatial & temporal event-state engine
                                                    |
                            Confidence / abstention / cooldown rules
                                                    |
                              Personal cue orchestration (Mimo)
                                                    |
                       Speech / optional haptics / accessible visuals
```

**Critical policy boundary:** Meta's wearable policies may restrict identification of people by face or voice and may require an explicit accessibility exception or approval. **Do not ship, bypass policy, or describe live biometric recognition as available until approval and supported API access are confirmed.** Design a safe alternate demo with explicit on-device mock identities / QR or NFC opt-in signals and camera-based **non-identifying** object/person tracking. Likewise, server-hosted Muse or SAM must not receive enrolled facial templates, identifying images, or voices when the privacy promise is that those stay on the phone. Design provider abstractions with policy-respecting local fallbacks.

**Event state model:** `personEnteredView`, `personApproaching`, `personNearby`, `personDeparted`, `personWaving`, `speakerStarted`, `cameraUnavailable`, `identityUncertain`. Events should have timestamps, observation source, consent and confidence state, expiry, and the latest associated region/direction. Face-expression, waving, and speaker-direction detection may fail; use conservative thresholds and user-configurable behavior. Do not infer emotional states, attraction, intent, or mental health.

**Privacy by design:** Process only what is needed for an active feature; don't retain continuous conversations or images. Any temporary event replay must be separately opt-in and have short, communicated retention. Account for bystanders in camera frames, informed consent for enrolled individuals, revocation, local encryption/keychain storage, visible recording indicators, and disclosure of any incidental cloud services. Treat accidental misidentification as more damaging than no identification.

## 20.10 SwiftUI engineering handoff — suggested module boundaries

```text
FamiliarApp/
  App/
    FamiliarApp.swift
    AppCoordinator.swift
  DesignSystem/
    FamiliarColors.swift
    FamiliarTypography.swift
    FamiliarComponents.swift
    AccessibilityPresets.swift
  Mimo/
    MimoView.swift
    MimoRenderer.swift
    MimoShaders.metal
    MimoStateMachine.swift
    MimoVoiceEnergy.swift
  Features/
    Onboarding/
    Today/
    Room/
    People/
    Enrollment/
    Privacy/
    Preferences/
    DemoSimulator/
  Glasses/
    GlassesConnectionManager.swift
    WearablesProvider.swift
    MockWearablesProvider.swift
  Perception/
    PerceptionProvider.swift
    OptInIdentityPolicy.swift
    SpatialEventEngine.swift
    CueConfidencePolicy.swift
  Audio/
    CueSpeaker.swift
    AudioPriorityCoordinator.swift
    OptionalHapticFeedback.swift
  Persistence/
    ConsentStore.swift
    ContactStore.swift
    UserPreferenceStore.swift
  Tests/
    VoiceOverFlowTests/
    LargeTextSnapshotTests/
    RecognitionAbstentionTests/
    ConsentRevocationTests/
    DemoScenarioTests/
```

**Build rule:** No fake controls. Every visible button must either navigate, change state, invoke a permission/SDK operation, or clearly say “Available in demo only” / “Coming later.” Treat mock providers as first-class development infrastructure so you can show the complete interface without falsely suggesting unavailable recognition capability.

## 20.11 Demo stage plan — 90 seconds, visually impressive and emotionally grounded

**0–15 seconds — Hook.** Show a quiet room. Narrator: “Most people see someone approaching and get a chance to say hello first. That's a piece of social life we rarely notice.”

**15–30 seconds — Familiar.** Fullscreen iPhone UI: Mimo takes a breath, recognizes glasses status, reveals the Room screen. “Familiar is a social awareness companion for people who are blind or have low vision.”

**30–55 seconds — Human moment.** Known enrolled Maya approaches. In approved live mode, on-device perception triggers; otherwise use a clearly labeled simulator and describe the exact simulated component. Audio: “Maya, approaching from your right.” Participant says, “Hey, Maya.” **Pause.** Let audience see the human interaction.

**55–70 seconds — Agency and consent.** Show a quick invited-person sign-up and visible “Only people who choose to be remembered” text. Demonstrate an immediate mute or deletion choice. Emphasize no covert identification.

**70–85 seconds — Differentiated interaction.** Toggle from Audio First to Enhanced Vision; the same cue becomes large, high-contrast type. Show the playful Muse-inspired original Mimo reacting without becoming the functional interface.

**85–90 seconds — Closing.** “We're not replacing human connection with AI. We're making human connection more accessible.”

## 20.12 Design inspiration and library reference list

Research / inspiration starting points, not blanket recommendations for direct code reuse:

- https://inspora.design — art direction, mobile compositions, visual hierarchy.
- https://designeer.xyz — detailed UI craft, accessible component patterns, inspiring structure.
- https://scrolltide.co — fluid/3D motion references; implement natively with Metal instead of web scroll effects.
- https://backgrounds.supply — ambient backgrounds, diffusion, glow studies. Avoid embedding a decorative image beneath crucial text in high-contrast mode.
- https://fontshare.com — alternative licensed typography exploration; retain native Dynamic Type and verify font licenses.
- https://cta.gallery — onboarding button and CTA hierarchy inspiration, translated to thumb-friendly native targets.
- https://footer.design — mostly web-oriented; adapt its idea of strong information architecture for app privacy/help sections, not literal mobile footers.
- https://reelfolio.io — polished storytelling/presentation inspiration for the demo or project showcase, not core iOS UI.
- https://libraries.dev — discover animation packages and inspiration; inspect licenses, maintenance and Swift/iOS support before adoption.

**Final directive:** Design the most lovable AI companion in the room, but make the human user — not the AI — the hero. Deliver delight for users with residual vision, independent full operation for screen-reader users, and observable trust for anyone who opts into being recognized.
