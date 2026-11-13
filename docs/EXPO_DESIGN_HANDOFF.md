# Familiar on Expo — design and build handoff

The React Native / Expo edition of the design that `docs/DESIGN_SPEC.md`, `docs/DESIGN_SYSTEM.md` and the `sahas` branch describe in SwiftUI. Same product, same promises, same look: an ivory canvas, white cards with soft corners, pill controls, Plus Jakarta Sans SemiBold, one luminous object per screen, and a **vision profile** that scales every size, weight, icon and hit target. Everything below is pinned to what is on npm in November 2026.

Drop this file into the Expo repo as `DESIGN.md` and point `AGENTS.md` / `CLAUDE.md` at it. Agents read it before touching UI.

Motto: *The finer things in life are felt, not seen.*

---

## 1. Stack

| Layer | Choice | Version (npm, Nov 2026) | Why |
|---|---|---|---|
| Runtime | `expo` | 58.0.x (React Native 0.88, built for iOS 27, New Architecture only) | Native tabs, loaders and server output are stable; `expo-glass-effect` reports liquid glass on iOS 26+ |
| Routing | `expo-router` | 58.0.x | File routes, `NativeTabs`, native stack sheets, `Link.Preview` / `Link.Menu` |
| Motion | `react-native-reanimated` + `react-native-worklets` | 4.7.x / 0.13.x | UI-thread animation; Reanimated 4 needs the New Architecture, which SDK 58 is |
| Gestures | `react-native-gesture-handler` | 3.5.x | `Gesture.Pan()`; wrap the root in `GestureHandlerRootView` |
| Drawing | `@shopify/react-native-skia` | 2.14.x | Radar, aurora, the vendored libraries.dev native ports, our Skia ports |
| Native SwiftUI | `@expo/ui` (`@expo/ui/swift-ui`) | 58.0.x | Real `Toggle`, `Slider`, `Picker`, `BottomSheet`, `ContextMenu`, `Gauge` inside a `Host` |
| Liquid glass | `expo-glass-effect` | 58.0.x | `GlassView` / `GlassContainer` on iOS 26+, falls back to `View` |
| Symbols | `expo-symbols` | 58.0.x | SF Symbols with weights that follow the vision profile |
| Haptics | `expo-haptics` | 58.0.x | Selection / impact / notification, one per user action |
| Fonts | `expo-font` config plugin + `PlusJakartaSans-*.ttf` | — | Embedded at build time, no flash. (`@expo-google-fonts/plus-jakarta-sans` 0.4.x is the JS-loaded alternative) |
| Toasts | `sonner-native` | 0.27.x | The cue toast (Sonner's author is Emil Kowalski, whose skills we follow) |
| Menus | `zeego` | 3.x | Native iOS context menus where `Link.Menu` does not fit |
| Maps | `expo-maps` | 58.0.x | Apple Maps for "where we met" |
| Storage | `react-native-mmkv` | 4.x | Preferences; the people store stays in the native module |
| Glasses | `@chrisgocode/expo-meta-wearables-dat` | 2.2.0 (DAT SDK 1.0) | Community Expo module; see §10 |
| Audio / speech / voice | Expo Modules wrapping the Swift on `main` | — | Do not rewrite `VoiceSpeaker`, `ElevenLabsTTS`, the cue policy or the perception pipeline in JS |

Install with `npx expo install <pkg>` so versions match the SDK. Run `npx expo-doctor` after every dependency change. Build with a **development build** (`npx expo run:ios`); Expo Go cannot load the glasses module, Skia shaders or our own Expo Modules.

---

## 2. Project shape

```
app/
  _layout.tsx                 ThemeProvider, GestureHandlerRootView, VisionProfileProvider, Toaster
  onboarding/                 welcome · capabilities · communicate · privacy · glasses   (stack, swipe pager inside)
  (tabs)/_layout.tsx          NativeTabs: Today · Room · People · You
  (tabs)/index.tsx            Today
  (tabs)/room.tsx             Room (radar + people list + camera stage)
  (tabs)/people/              index · [id] · places · invite
  (tabs)/you/                 index · accessibility · voice · privacy · demo
  consent.tsx                 presentation: 'formSheet' — the consent card
  listening.tsx               presentation: 'transparentModal' — Poyo listening overlay
modules/
  familiar-perception/        Swift Expo Module: frames → tracks, matches, cues (events only, never pixels)
  familiar-voice/             Swift Expo Module: VoiceSpeaker queue, ElevenLabs + Apple TTS, SpeechPreferences
  familiar-audio/             Swift Expo Module: AVAudioSession Route A, transcriber, wake word
src/
  design/   tokens.ts · type.ts · visionProfile.tsx · surfaces.tsx · pills.tsx · aurora.tsx
  motion/   springs.ts · transitions.ts · GlassEdgePager · CueToast · ShimmerText · NumberPop · ParticleBurst · SlidingPillSegment · GooeyMenu
  kits/     border-beam-native/ · thinking-orbs-native/ (vendored from libraries.dev) · voice-glow-native/ · bot-avatar-native/ (our Skia ports)
  companion/ Mimo.tsx (the avatar) · MimoStatusLine.tsx
  web/      Astryx-based pages: invitation page, landing (Expo Web / Next)
```

One rule above all: **JavaScript never sees a camera frame, a face vector or a photo.** Native modules consume frames and emit small JSON events. That is how "faces never leave the phone" stays provable in a React app.

---

## 3. The native ↔ JS boundary

| Event (native → JS) | Payload | Drives |
|---|---|---|
| `tracks` (≤ 10 Hz) | `[{ id, known: bool, name?, clockHour, distanceBand, approaching }]` | Room radar and list |
| `cue` | `{ text, priority, personId?, kind: 'person'\|'hazard'\|'consent'\|'poyo' }` | Cue toast, Mimo pose, nearby card beam |
| `consentPrompt` / `consentResult` | `{ question, name? }` / `{ saved: bool, personId? }` | Consent sheet |
| `speaking` | `{ state: 'idle'\|'listening'\|'thinking'\|'speaking', level: 0–1 }` | Mimo state, voice glow level |
| `glasses` | `{ linked, streaming, fps, battery? }` | Readiness, Today status chip |

Commands (JS → native) mirror the Swift `Command` router: `whoIsHere`, `rememberThem`, `pause`, `resume`, `repeatLast`, `setCueLevel(quiet|normal|chatty)`, `setVisionProfile`, `remove(personId)`, `removeEveryone`. The model never gets a new verb from JS.

Shared values, not state: the `level` in `speaking` is written straight into a Reanimated shared value from the event listener so glows and meters never re-render React.

---

## 4. Tokens (carried over unchanged)

`src/design/tokens.ts`

```ts
export const color = {
  canvas: '#F7F8F5', canvasSecondary: '#EEEDEA', surface: '#FFFFFF',
  ink: '#172236', inkSecondary: '#576477', stroke: '#E4E5E8',
  ocean: '#1F6CD6', onOcean: '#FFFFFF', lilac: '#A08EF4', mint: '#75D9CF', peach: '#F5C9AC',
  success: '#127353', warning: '#925A12', danger: '#B42336', focus: '#1B64D8',
  aurora: { blue: '#2779E7', orange: '#F5A66B', purple: '#A08EF4', sky: '#79C9F7' },
  hc: { ink: '#172236', stroke: '#26364B', canvas: '#FFFFFF', ocean: '#0053B8', lilac: '#6741B8', mint: '#00776D', focus: '#003B8E' },
} as const;
export const radius = { hero: 32, card: 26, control: 18, pill: 999 } as const;
export const space  = { margin: 22, card: 20, gap: 12, tight: 8 } as const;
```

Rules: `ocean` is the only accent that may carry text (5.0:1 on white). Pastel `mint` / `lilac` are decoration; when a colour **means** something (a known-person dot, a state tint) use the high-contrast `hc.*` value through `useVisionScale().paint(...)`. Tab tint uses `DynamicColorIOS({ light: color.ocean, dark: '#79C9F7' })` because the iOS 26 tab bar re-colours itself from the content behind it.

### Type (Plus Jakarta Sans; base pt, × `textScale`)

| Role | Base | Weight | Tracking | Line height |
|---|---|---|---|---|
| display | 40 | Bold | −0.02em | 1.05 |
| titleXL | 32 | profile weight | −0.015em | 1.1 |
| title | 24 | profile weight | −0.01em | 1.15 |
| companion | 20 | profile weight | 0 | 1.25 |
| control | 19 | profile weight | 0 | 1.2 |
| body | 17 | profile weight | 0 | 1.5 |
| paragraph | 17 | Regular | 0 | 1.5 |
| supporting | 15 | Medium | +0.005em | 1.4 |
| micro | 13 | profile weight | +0.01em | 1.35 |
| mono | 13 | Medium, `fontVariant: ['tabular-nums']` | 0 | 1.35 |

Font families are the file names: `PlusJakartaSans-Regular`, `-Medium`, `-SemiBold`, `-Bold` (keep the files named after their PostScript names so iOS and Android agree). Register them in `app.json`:

```json
["expo-font", { "fonts": ["./assets/fonts/PlusJakartaSans-Regular.ttf", "./assets/fonts/PlusJakartaSans-Medium.ttf", "./assets/fonts/PlusJakartaSans-SemiBold.ttf", "./assets/fonts/PlusJakartaSans-Bold.ttf"] }]
```

Every label goes through `<T role="body">` (`src/design/type.ts`). System font scaling stays on (`allowFontScaling`), capped with `maxFontSizeMultiplier` (2.0 balanced, 1.6 low vision, 1.3 severe) so the profile and Dynamic Type compound without breaking layouts. Never `fontFamily: 'System'` in screens.

### Vision profile → scale

`VisionProfileProvider` reads the stored profile (MMKV key `visionProfile`, default `balanced`) and folds in `AccessibilityInfo`: `isReduceMotionEnabled → simplifyMotion`, `isDarkerSystemColorsEnabled` (Increase Contrast) `→ highContrast`, `isBoldTextEnabled → bold`, `isReduceTransparencyEnabled → opaqueSurfaces`, `isScreenReaderEnabled → spokenFirst`. System settings always win.

| Profile | textScale | iconScale | weight | hitTarget | highContrast | simplifyMotion | spokenFirst |
|---|---|---|---|---|---|---|---|
| Balanced | 1.0 | 1.0 | 600 | 52 | no | no | no |
| Low vision | 1.25 | 1.2 | 600 | 60 | yes | no | no |
| Severe | 1.6 | 1.5 | 700 | 72 | yes | yes | no |
| Non-visual | 1.0 | 1.0 | 600 | 60 | no | yes | yes |

Derived: `strokeWidth` 1 / 2, `shadowOpacity` 0.05 / 0, `surfaceOpacity` 0.94 / 1, `prefersStackedLayout` (textScale ≥ 1.5), `points(n)`, `icon(n)`, `spacing(n)` (grows at half the text rate), `spring(preset)` (returns `withTiming(…, 200ms)` crossfades when motion is simplified). Differentiate Without Color is not exposed by React Native; `familiar-audio` exports a one-line `UIAccessibility.shouldDifferentiateWithoutColor` getter for the mic meter.

---

## 5. The Apple feel

Taken from Emil Kowalski's `apple-design` and `animate-expo` skills (§13) and Apple's fluid-interfaces talk. These are rules, not taste notes.

**Navigation is native.** `NativeTabs` for the four tabs (liquid glass for free on iOS 26, `minimizeBehavior="onScrollDown"`), native stack for everything else, `headerLargeTitleEnabled` on People and You, `presentation: 'formSheet'` for the consent card and settings sub-sheets, `Link.Preview` for person cards and `Link.Menu` for their quick actions. Tabs do not animate (`animation: 'none'`).

```tsx
// app/(tabs)/_layout.tsx
import { NativeTabs } from 'expo-router/native-tabs';
export default () => (
  <NativeTabs minimizeBehavior="onScrollDown">
    <NativeTabs.Trigger name="index"><NativeTabs.Trigger.Icon sf="sun.max.fill" md="wb_sunny" /><NativeTabs.Trigger.Label>Today</NativeTabs.Trigger.Label></NativeTabs.Trigger>
    <NativeTabs.Trigger name="room"><NativeTabs.Trigger.Icon sf="dot.radiowaves.left.and.right" md="radar" /><NativeTabs.Trigger.Label>Room</NativeTabs.Trigger.Label></NativeTabs.Trigger>
    <NativeTabs.Trigger name="people"><NativeTabs.Trigger.Icon sf="person.2.fill" md="group" /><NativeTabs.Trigger.Label>People</NativeTabs.Trigger.Label></NativeTabs.Trigger>
    <NativeTabs.Trigger name="you"><NativeTabs.Trigger.Icon sf="person.crop.circle" md="account_circle" /><NativeTabs.Trigger.Label>You</NativeTabs.Trigger.Label></NativeTabs.Trigger>
  </NativeTabs>
);
```

**Materials mark hierarchy.** Heavier material = structure (tab bar, sheet chrome); lighter = the one interactive floating thing (the "Who's here?" dock, the cue toast). Never stack two light translucent surfaces. Modals get a scrim; non-blocking panels do not. Under Reduce Transparency every glass or blur becomes an opaque `surface` with a `stroke` border.

**Controls are real.** Toggles, sliders, pickers and the speech-rate stepper are `@expo/ui/swift-ui` inside a `Host`, so they look, sound and read exactly like Settings:

```tsx
import { Host, Form, Section, Toggle, Slider, Picker } from '@expo/ui/swift-ui';
<Host style={{ flex: 1 }}>
  <Form>
    <Section title="Cues">
      <Toggle label="Speaking first" value={speakingFirst} onValueChange={setSpeakingFirst} />
      <Slider value={rate} min={0.7} max={1.2} onValueChange={setRate} />
    </Section>
  </Form>
</Host>
```

**Symbols, not icon fonts.** `expo-symbols` `SymbolView` with `weight` following the profile (`semibold` / `bold`) and `size={scale.icon(20)}`.

**Touch responds on press-in.** Scale to 0.97 in 100 ms ease-out, haptic on the same frame, `hitSlop` so every target is ≥ 44 pt (profiles raise it to 52–72). Under `simplifyMotion` the press is a dim to 0.8 instead of a squeeze.

**Type is tuned per size.** Tracking and leading from the table in §4; weight, size and leading together carry hierarchy. Never flat grey text over a translucent surface.

---

## 6. Motion

`src/motion/springs.ts` — the only springs allowed:

| Preset | Reanimated | Use |
|---|---|---|
| `settle` | `withSpring(v, { duration: 400, dampingRatio: 1 })` | Anything that fades or grows in without a finger |
| `snapBack` | `withSpring(v, { duration: 400, dampingRatio: 0.8, velocity })` | Release after a drag; pass the gesture velocity |
| `sheet` | `withSpring(v, { duration: 300, dampingRatio: 0.8, velocity, overshootClamping: true })` | Sheets, drawers, the pager's edge |
| `press` | `withTiming(0.97, { duration: 100, easing: Easing.out(Easing.quad) })` | Press-in |
| `toggle` | `withTiming(v, { duration: 180, easing: Easing.out(Easing.cubic) })` | Chips, segments, toggles |
| `crossfade` | `withTiming(v, { duration: 200 })` | Everything when `simplifyMotion` |

Rules (from `animate-expo`):
- Animate **transform and opacity only**. Never width, height, margin, top, Android `elevation` or `BlurView` intensity.
- Enter from `scale 0.9–0.97` + `opacity 0`, never from `scale 0`. Ease-out for enter and exit, ease-in-out for on-screen moves, linear for constant motion, **never ease-in**. UI under 300 ms; screen transitions use the platform default.
- Springs for anything a finger touched (they carry velocity through interruptions); timing for the rest. Bounce only after momentum.
- Interruptible always: start from the live value, carry velocity, rubber-band at edges (0.55), decompose X and Y into separate springs, project momentum before picking a snap target.
- Gesture and scroll handlers never call `setState`. Shared values + `useAnimatedStyle`; `scheduleOnRN` (not `runOnJS`) in `onEnd` or at a `useAnimatedReaction` threshold, never per frame. `'worklet'` on anything called from a worklet. No `PanResponder`.
- `entering` / `exiting` / `itemLayoutAnimation` for layout changes; never `entering` on virtualized rows (animate the container).
- Reduced motion: `useReducedMotion()` on every animation. Keep opacity and colour changes that explain state; drop translate, scale, parallax, overshoot; stack `animation: 'fade'`.
- Enable `CADisableMinimumFrameDurationOnPhone` in `infoPlist` for 120 Hz; the frame budget is then 8 ms. Test on a release build on the slowest supported phone.
- Haptics: `selectionAsync` for stepped values, `impactAsync(Light)` for snaps, `Medium` for destructive, `notificationAsync` for success/error. Same frame as the visual, once per action, never the only feedback.

Motion library (ports of the SwiftUI set, same names): `GlassEdgePager` (horizontal pager with `GlassView` edge strips that brighten with drag progress), `CueToast` (on `sonner-native`, 5 s, "Repeat" action), `ShimmerText` (Skia gradient mask), `NumberPop`, `ParticleBurst` (Skia, ≤ 40 particles, off under `simplifyMotion`), `SlidingPillSegment`, `GooeyMenu` (Skia `Blur` + `ColorMatrix` threshold, see §7), `errorShake`, `skeletonReveal`, `liftOnPress`, `tilt3D`.

Choreography: on Today, Mimo leads, the status line follows at +60 ms, the dock last at +120 ms; everything else stays still. On a person cue, the nearby card's beam starts on the same frame as the toast and the haptic.

---

## 7. libraries.dev

What exists, honestly:

| Library | Web package (React 18+, MIT) | Native | Where we use it |
|---|---|---|---|
| Border beam | `border-beam` 1.4 — `<BorderBeam size colorVariant theme active borderRadius duration strength staticColors>` | **`border-beam-native` 0.1.0** in the monorepo at `packages/border-beam/ports/react-native/border-beam-native` (Skia + Reanimated, Expo-compatible, beta, iOS-verified, Android untested, **not on npm**) | Nearby card for 6 s after a person cue; consent question; anything loading > 3 s |
| Thinking orbs | `thinking-orbs` 0.3 — `<ThinkingOrb state size={64\|20} theme speed paused>`; states `working searching solving listening connecting weaving composing breathing shaping` | **`thinking-orbs-native` 0.1.0** at `packages/thinking-orbs/ports/react-native/thinking-orbs-native` (same stack, same status) | `MimoStatusLine`; any wait ≥ 2 s |
| Bot avatars | `bot-avatars` 0.2 — `<BotAvatar type state face size color ink shading hat glasses interactive paused seed aria-label>`; 18 shapes; states `default working sleeping` | none | **Mimo** = `type="blob" face="mouth" color="#75D9CF" ink="#172236" shading="smooth"`. Native: our Skia port `src/kits/bot-avatar-native` (blob shape only, four states, still pose under reduced motion) |
| Voice | `voice-glow` 0.3 — `<VoiceBeam type={'default'\|'pill'\|'mobile'} level stream active colorVariant borderRadius theme strength reach spread sensitivity threshold attack release>` | none | Consent card and listening overlay. Native: our Skia port `src/kits/voice-glow-native` (bottom glow, `level` from the `speaking` shared value, `colorVariant="ocean"`) |
| Gooey | `liquid-gooey` — `<Liquid>` | none | "Add someone" menu. Native: Skia `Group` with `Blur` + `ColorMatrix` alpha threshold (the classic goo filter) |
| Liquid metal | `metal-fx` 2.0 — `<MetalFx>` | none | Web surfaces only. Native Today uses a `GlassView` ring instead (one per screen) |
| Image | `img-fx` (needs `three`) | none | Not used |
| Voice ring, distortion waves, magnetic UI | `voice-ring` 0.2 (web); DistortionWaves and Magnet are SwiftUI / model files | — | Not used; Magnet model files need a Pro licence for commercial apps |

Native ports are not published, so **vendor them**: copy each `…-native/src` folder into `src/kits/<name>/`, keep their README and MIT notice, and add the peer deps (`@shopify/react-native-skia`, `react-native-reanimated`). Both mirror the web props; `borderRadius` must be explicit (no DOM auto-detection). Re-check the monorepo before each release; if they land on npm, switch to the package.

Placement rules (the author's, from the libraries.dev skill): under 2 s of waiting, nothing; 2 s or more, a thinking orb beside a label; more than 3 s, also a border beam on the element doing the work, `active` bound to the loading flag. Never guess a prop: read `skills/libraries-dev/references/*.md` in the monorepo first.

Accessibility of the kits: web `BotAvatar` and `ThinkingOrb` render `role="img"` with a per-state label and freeze under `prefers-reduced-motion`; rotating `BorderBeam` types do **not** respect reduced motion on their own, so bind `active={!simplifyMotion && loading}`. Our native ports do the same through `useReducedMotion()` and `accessibilityRole="image"` + `accessibilityLabel`. Mimo is decorative: `accessibilityElementsHidden` on the avatar, the status line carries the text.

Web surfaces (Expo Web build, invitation page, landing) use the npm packages directly; they are canvas/CSS and need no bundler config.

---

## 8. Liquid glass

**Native (the app):** `expo-glass-effect`.

```tsx
import { GlassView, GlassContainer, isLiquidGlassAvailable, isGlassEffectAPIAvailable } from 'expo-glass-effect';
const glassOK = isGlassEffectAPIAvailable() && isLiquidGlassAvailable() && !reduceTransparency;
<GlassContainer spacing={12}>
  <GlassView glassEffectStyle="regular" isInteractive tintColor={color.ocean + '22'} style={pill} />
  <GlassView glassEffectStyle="clear" style={pill} />
</GlassContainer>
```

- `glassEffectStyle`: `'regular' | 'clear' | 'none'` or `{ style, animate: true, animationDuration }`. Switch to `'none'` to hide; **never set `opacity < 1`** on a `GlassView` or its parents (Apple's rule; the glass stops rendering). Animate a wrapper's opacity with Reanimated if you must fade.
- `GlassContainer spacing` is the distance at which pills start merging; use it for the Pause / Remember / Who's-here dock on Today.
- iOS 26+ only; elsewhere it is a plain `View`, so always give it a `surface` background and `stroke` border as the fallback look. `isLiquidGlassAvailable()` can be true while the user has limited the effect, so also check `AccessibilityInfo.isReduceTransparencyEnabled()`.
- `@callstack/liquid-glass` 0.8 is the alternative if Expo's component lacks something; do not ship both.
- Where glass lives: the Today dock, the cue toast surface, `GlassEdgePager` edge strips, the listening overlay's bottom bar. Never behind body text, never nested.

**Web (invitation page, landing):** `liquid-glass-react` 1.1 (github.com/rdev/liquid-glass-react, MIT).

```tsx
import LiquidGlass from 'liquid-glass-react';
<LiquidGlass displacementScale={48} blurAmount={0.08} saturation={130} aberrationIntensity={1.5} elasticity={0.1} cornerRadius={26} mode="standard" overLight>
  …hero content…
</LiquidGlass>
```

Defaults are `displacementScale 70, blurAmount 0.0625, saturation 140, aberrationIntensity 2, elasticity 0.15, cornerRadius 999, mode 'standard'`. `shader` mode is the most accurate and least stable; Safari and Firefox show blur but no displacement, so design the fallback first. Wrap it in a `prefers-reduced-transparency` check and never put paragraph text inside it.

---

## 9. Astryx (Meta)

Meta's open-source React design system (`@astryxdesign/core` 0.7.x, beta, MIT, React 19+, StyleX under the hood, 150+ accessible components, seven themes: neutral, butter, chocolate, matcha, stone, gothic, y2k). It is a **React DOM** library, not React Native, so it never renders inside native screens. Use it for:

1. The other person's one-page **invitation / consent web page** (spec screens 13–14) and the enrollment-complete page.
2. The **landing / Devpost** site and any team dashboard.
3. Its **agent tooling**: an MCP server and dense docs that keep agents from inventing props.

Setup (web package or `apps/web`):

```bash
npm install @astryxdesign/core @stylexjs/stylex @astryxdesign/theme-neutral @astryxdesign/cli
npx @astryxdesign/cli init --features agents      # project agent docs
npx @astryxdesign/cli theme add neutral           # generates the theme module and CSS
```

```css
@import '@astryxdesign/core/reset.css';
@import '@astryxdesign/core/astryx.css';
```

```tsx
import { Theme } from '@astryxdesign/core/theme';
import { Button } from '@astryxdesign/core/Button';
import { themes, defaultThemeSlug } from './astryx-themes';
<Theme theme={themes[defaultThemeSlug]}><Button label="Yes, remember me" onClick={onYes} /></Theme>
```

Agent workflow: `npx @astryxdesign/cli build "<idea>"` → `template <name> <path>` → `component <Name> --dense` for every component used; `docs tokens --dense` for the token reference; `astryx doctor` when something looks off. MCP (two tools, `search` and `get`):

```bash
claude mcp add --transport http astryx https://astryx.atmeta.com/mcp
```

Theme the web pages with our tokens through Astryx's theme CLI (`theme template` → edit → `theme build`) so the invitation page is the same ivory, ink and ocean as the phone. Keep the Astryx reset off the native bundle (it is CSS).

---

## 10. Glasses in Expo

`@chrisgocode/expo-meta-wearables-dat` 2.2.0 wraps Meta's DAT SDK 1.0 (iOS and Android). Community-maintained, not Meta's. Requirements: Expo 52+, RN 0.76+, iOS 17.2+, Xcode 16+, Swift 6, a development build (never Expo Go), the Meta AI app paired with the glasses. **New Architecture is listed as untested** and SDK 58 is New-Architecture-only: build and stream on day one; if it fails, the fallback is a thin Expo Module over `MWDATCore` + `MWDATCamera` lifted from `Familiar/Sources/GlassesFrameSource.swift` on `main`.

```json
["@chrisgocode/expo-meta-wearables-dat", { "urlScheme": "familiar", "metaAppId": "<id or omit for Developer Mode>", "clientToken": "<token>", "bluetoothUsageDescription": "Familiar connects to your glasses over Bluetooth." }]
```

```tsx
const { isConfigured, registrationState, devices, startRegistration, createSession, startSession, stopSession, addCameraToSession, capturePhoto } =
  useMetaWearables({ onStreamStateChange: setStreamState });
const id = await createSession(); await startSession(id);
await addCameraToSession(id, { resolution: 'medium', frameRate: 24 });   // 504×896 HEVC, Bluetooth Classic
```

Keep the product facts from the Swift build: Bluetooth Classic transport (Wi-Fi mutes app audio), Route A audio (phone mic in, glasses A2DP out; opening the glasses' HFP mic ends the stream), double-tap = "who's here?", capture button = "remember them". Mock device works in debug simulator builds for the UI; real frames need a phone. Meta still marks inputs, motion, speech, voice and stream-audio as experimental and says apps using them cannot yet be published, so gate those behind a `DEV` flag.

The camera frames must reach `familiar-perception` natively. If the module only exposes a stream view, subclass or fork its iOS side to forward `CVPixelBuffer`s to our module; JS keeps receiving events, not pixels.

---

## 11. Screens (what each is made of)

| Screen | Components |
|---|---|
| Onboarding (5 pages, `GlassEdgePager`) | Welcome: Mimo on the aurora, "Because everyone deserves to feel seen.", motto, Begin / Explore a demo · Capabilities: can / cannot lists · Communicate: vision-profile `SlidingPillSegment` with live preview and a sample cue · Privacy: four promises, Continue opens the permissions checklist · Glasses: register or Continue |
| Today | Mimo (hero) + `MimoStatusLine` (orb) · headline · `GlassContainer` dock: Pause · Remember them · Who's here? · cue-level segment · nearby card (`BorderBeam` 6 s after a cue, Call when a number exists) · consent status · last error with `errorShake` |
| Room | counts with `NumberPop` · **radar** (Skia half-disc, five bands, three rings, mint dots for known, hollow for strangers; one `accessibilityLabel` sentence) · people list · camera stage (`EMWDATStreamView` or phone camera) · Pause / Resume chip |
| People | cards with photo or monogram · search · All / Recent chips · **Add someone** `GooeyMenu` (Ask them out loud → consent sheet; Show invitation → Astryx web page QR) · detail: Call · Text · Where we met (`expo-maps`) · Remove · `Link.Preview` on cards |
| You | hub · Accessibility (profile, haptics, speech rate / volume, keep cue text, Mimo visibility, iOS settings mirror) · Voice and cues (speaking first, volume-button action) · Privacy dashboard ("Your people. Your control.", counts, map, Remove everyone) · Demo controls |
| Consent sheet (`formSheet`) | question in a `BorderBeam` · `VoiceGlow` at the bottom while listening · YES / NO pills (hitTarget) · `ParticleBurst` on yes · the few-second clip is recorded natively |
| Listening overlay (`transparentModal`) | Poyo's wake state: `VoiceGlow` mobile type, live transcript line, Cancel |
| Cue toast (global) | every spoken line as text for 5 s, Repeat action, `GlassView` surface |

Empty, loading and error states exist for every screen (`break-ui` skill, §13): long names, zero people, 40 people, no glasses, no network, denied permissions.

---

## 12. Accessibility acceptance

- Every control: `accessibilityRole`, `accessibilityLabel`, `accessibilityHint` ("Calls Marcus"), `accessibilityState`. Grouped rows are one element (`accessible` on the row). Nothing is colour-only.
- The radar reads as one sentence: "Three people. Maya, two o'clock, close. Two strangers." Scores are never shown or spoken.
- Live regions: the cue toast uses `accessibilityLiveRegion="polite"` and `AccessibilityInfo.announceForAccessibility` for hazards.
- Profiles: all four render every screen without truncation; chips wrap, side-by-side rows stack when `prefersStackedLayout`.
- System settings map: Reduce Motion → crossfades, no parallax, still aurora, Mimo still pose · Increase Contrast → `hc.*` paint, 2 pt ink strokes, no shadows · Reduce Transparency → opaque surfaces, no glass or blur · Bold Text → weight 700 · Larger Text → compounds up to the multiplier cap · VoiceOver → spoken-first hints, no autoplay motion.
- Speech rate and volume are the wearer's: sliders in You write MMKV keys the voice module reads.
- Screen reader test every PR: VoiceOver on the slowest supported iPhone, Switch Control on the consent sheet.

---

## 13. Agent setup

Install once per machine:

```bash
npx skills@latest add emilkowalski/skills                 # 18 design-engineering skills (MIT)
npx skills add https://github.com/Jakubantalik/Libraries.dev --skill libraries-dev   # the libraries.dev skill
npx @astryxdesign/cli init --user                          # global Astryx skill
claude mcp add --transport http astryx https://astryx.atmeta.com/mcp
```

Which Emil skills, when:

| Skill | Use it |
|---|---|
| `animate-expo` | Before any Reanimated, gesture, sheet or haptic code (the §6 rules come from it) |
| `apple-design` | When composing a screen or material hierarchy |
| `gestures` | The pager, sheet dismissal, radar drag |
| `choreograph` | Multi-element entrances (Today, consent yes) |
| `find-animation-opportunities` / `remove-animations` | Once per screen, both directions |
| `review-animations` + `animation-performance` | Every PR that touches `src/motion` |
| `break-ui` | After each screen, with worst-case data |
| `pick-ui-library` | Before hand-rolling a toast, menu or dialog (web: Sonner, base-ui, cmdk, NumberFlow; native: `sonner-native`, `zeego`, `@expo/ui`) |
| `learn-taste` | At the end of a session: corrections become rules in this file |

Loop for every UI PR: build → run on device → `review-animations` → `break-ui` → VoiceOver pass → screenshots (§14).

---

## 14. Testing and screenshots

- Unit and component: `jest-expo` + `@testing-library/react-native`; the vision-scale math, type roles, cue-toast queue and radar sentence builder are pure functions with tests.
- Native modules: keep the Swift tests from `main` (perception, cue policy, speaker queue) inside each module's `ios/Tests`.
- Flows and screenshots: Maestro (`.maestro/*.yaml`) on an iPhone 17 simulator with the mock glasses device; `takeScreenshot` for Welcome, Today, Room, People, consent sheet, Accessibility settings at `balanced` and `severe`. Screenshots are committed under `docs/snapshots/`.
- Performance: `npx expo run:ios --configuration Release` on the oldest supported phone; the dev client and Expo Go lie about frame rate.

---

## 15. Secrets and product rules (unchanged)

- No key in the repo or in `EXPO_PUBLIC_*`. Keys come from `.env.local` (git-ignored) through `app.config.ts` into the native modules' `Info.plist`; the JS bundle never holds `ELEVENLABS_API_KEY`, `META_MODEL_API_KEY`, `MODAL_*`.
- Meta Model API: Standard tier only, never `-contributor`.
- Only text or face-redacted 512 px frames leave the phone; strangers are never named or described; no mood inference; the app never sends a message for the wearer; nobody is added without their spoken or tapped yes.

---

## 16. Known risks

- `@chrisgocode/expo-meta-wearables-dat` on the New Architecture is untested by its author; SDK 58 requires it. Verify first; fallback in §10.
- The libraries.dev native ports are 0.1.0, iOS-verified only and unpublished; visual parity with the web demos is still being tuned by the author. Vendoring means we own fixes.
- `GlassView` on iOS 26 betas could crash without `isGlassEffectAPIAvailable()`; keep the guard even on iOS 27 builds.
- `@expo/ui` components live inside a `Host`; mixing them with RN views in one row needs explicit sizing (`matchContents` or a fixed height).
- Astryx is 0.7.x beta: expect API churn, pin exact versions, run `astryx upgrade --list` before bumping.
- `liquid-glass-react` shows no displacement in Safari and Firefox; the page must look finished without it.
- Expo Web is not a target for the app's native screens (Skia, glass and `@expo/ui` are native); only the Astryx pages ship on web.

---

## 17. Day one

1. `npx create-expo-app familiar --template tabs` (SDK 58), add the packages in §1 with `npx expo install`, then `npx expo-doctor`.
2. Fonts (§4), tokens, `VisionProfileProvider`, `<T>` and the pill styles; render the Design System gallery route at all four profiles.
3. `NativeTabs` layout with SF Symbols; empty screens with headers and the cue toast.
4. Vendor `border-beam-native` and `thinking-orbs-native`; write the Skia `bot-avatar-native` blob and `voice-glow-native`; Mimo on the aurora on Today.
5. Add the glasses module, prebuild, register, stream to `EMWDATStreamView` on a phone. Decide the §10 fallback the same day.
6. Create the three Expo Modules by moving Swift from `main`; wire `tracks`, `cue` and `speaking` events into Room and Today.
7. Consent sheet, People, You; Maestro screenshots; `review-animations` and `break-ui` on each.
8. Invitation page with Astryx; QR from the People menu.
