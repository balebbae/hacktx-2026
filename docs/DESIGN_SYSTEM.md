# Familiar design system (`Familiar/UI/Design/`)

Sleek, minimal, premium: an ivory canvas, white cards with 26 pt corners, pill controls, large clean type in Plus
Jakarta Sans SemiBold, and one luminous object per screen (Mimo or the aurora). Every size, weight, icon and hit
target follows the user's **vision profile**, read from the environment. Motto: *The finer things in life are felt, not seen.*

## Files
| File | Holds |
|---|---|
| `VisionProfile.swift` | `VisionProfile`, `VisionScale`, `EnvironmentValues.visionScale`, `.visionScale(_:)`, `.visionProfile(_:)`, `.visionHitTarget(_:)` |
| `Typography.swift` | `FamiliarFont.jakarta(…)`, `FamiliarFont.jakartaFixed(…)`, `FamiliarType.*(scale)`, deprecated static shims, `.visionIcon(_:base:)` |
| `Theme.swift` | `FamiliarPalette` tokens + scale helpers, `SurfaceCard` / `.surfaceCard()`, `.familiarCanvas()`, `PrimaryPillStyle`, `AccentPillStyle`, `GhostPillStyle` |
| `AuroraBackground.swift` | `AuroraBackground(intensity:mood:)`, `AuroraMood`, `AuroraPalette`, `AuroraMath` |
| `Components.swift` | `Eyebrow`, `StatusChip`, `MicMeter`, `CueTicker`, `PrivacyBanner`, `Monogram`, `NearbyPersonCard` |
| `DesignSystemGallery.swift` | One page with everything, previewed at all four profiles |

## Vision profile → scale
`AppState.visionProfile` (UserDefaults key `visionProfile`, default `.balanced`) is set at the root once:
`RootView().visionProfile(state.visionProfile)`. That modifier folds in the system settings (Reduce Motion →
`simplifyMotion`; Increase Contrast → `highContrast`; Bold Text → `.bold`) and publishes a `VisionScale`. System
settings always win. **Reduce Transparency** is not a palette switch: it only makes translucent surfaces opaque, and
`SurfaceCard`, `GhostPillStyle`, `StatusChip` and `AuroraBackground` read `accessibilityReduceTransparency` directly.
**Differentiate Without Color** is read by `MicMeter` (inactive bars become outlines).

| Profile | textScale | iconScale | weight | hitTarget | highContrast | simplifyMotion | spokenFirst |
|---|---|---|---|---|---|---|---|
| Balanced | 1.0 | 1.0 | semibold | 52 | no | no | no |
| Low vision | 1.25 | 1.2 | semibold | 60 | yes | no | no |
| Severe | 1.6 | 1.5 | bold | 72 | yes | yes | no |
| Non-visual | 1.0 | 1.0 | semibold | 60 | no | yes | yes |

Derived: `strokeWidth` (1 / 2 pt), `shadowOpacity` (0.05 / 0), `surfaceOpacity` (0.94 / 1), `prefersStackedLayout`
(textScale ≥ 1.5), `points(_:)` (× textScale), `icon(_:)` (× iconScale), `spacing(_:)` (grows at half the text rate),
`animation(_:)` (nil when motion is simplified).

## Type scale (Plus Jakarta Sans; sizes in pt, already × textScale)
| Role | Base | Balanced | Low vision | Severe | Non-visual | Weight | relativeTo |
|---|---|---|---|---|---|---|---|
| `display` | 40 | 40 | 50 | 64 | 40 | Bold | largeTitle |
| `titleXL` | 32 | 32 | 40 | 51 | 32 | scale.weight | title |
| `title` | 24 | 24 | 30 | 38 | 24 | scale.weight | title2 |
| `companion` | 20 | 20 | 25 | 32 | 20 | scale.weight | title3 |
| `control` | 19 | 19 | 24 | 30 | 19 | scale.weight | body |
| `body` | 17 | 17 | 21 | 27 | 17 | scale.weight | body |
| `paragraph` | 17 | 17 | 21 | 27 | 17 | Regular | body |
| `supporting` | 15 | 15 | 19 | 24 | 15 | Medium (SemiBold when bold) | subheadline |
| `micro` | 13 | 13 | 16 | 21 | 13 | scale.weight | footnote |
| `mono` | 13 | 13 | 16 | 21 | 13 | Medium, tabular digits | footnote |

Dynamic Type still applies on top through `relativeTo`. `FamiliarFont.jakarta(size, weight:, relativeTo:)` picks
`PlusJakartaSans-Regular/-Medium/-SemiBold/-Bold` by weight and falls back to `.system(design: .rounded)`, scaled by
`UIFontMetrics` for the same text style, if the fonts are missing (checked once with `UIFont(name:size:)`).
`FamiliarFont.jakartaFixed(size, weight:)` is the fixed-size variant for glyphs whose frame is already sized by the
profile (the monogram letter): Dynamic Type does not apply, so they cannot outgrow their container.
`.visionIcon(scale, base:)` sizes a symbol through the Jakarta font and sets `.fontWeight(scale.weight)` explicitly.
The old `FamiliarType.title` statics still compile but are deprecated; they render the balanced design.

## Colour tokens
`canvas #F7F8F5` · `canvasSecondary #EEEDEA` · `surface #FFFFFF` · `ink #172236` · `inkSecondary #576477` ·
`stroke #E4E5E8` · `ocean #1F6CD6` (5.0:1 on white, so it works as text too) · `onOcean #FFFFFF` (the label on an
ocean fill; deep navy `#0B1A33` in dark mode) · `lilac #A08EF4` · `mint #75D9CF` · `peach #F5C9AC` ·
`success #127353` · `warning #925A12` · `danger #B42336` · `focus #1B64D8` (each with a dark value).

High-contrast alternatives (spec §20.6) are reached through the scale helpers: `FamiliarPalette.ink(scale)`,
`inkSecondary(scale)`, `stroke(scale)` (→ `#26364B`), `surface(scale)` (always opaque), `canvas(scale)` (pure white),
`ocean(scale)` (→ `#0053B8`), `lilac(scale)` (→ `#6741B8`), `mint(scale)` (→ `#00776D`), `focus(scale)` (→ `#003B8E`).
Use the `(scale)` form whenever the colour carries meaning (a "known" dot, a tint on a state icon); the pastel
`mint`/`lilac` constants are for decoration only. Aurora stops: `auroraBlue #2779E7`, `auroraOrange #F5A66B`,
`auroraPurple #A08EF4`, `auroraSky #79C9F7`. Radii: hero 32, card 26, control 18; margin 22.

## Surfaces and pills
- `.surfaceCard(radius:padding:)`: **pass the balanced base padding** (default 20); the modifier applies
  `scale.spacing(padding)` itself. The shadow is drawn under the shape only (never under the text or stroke) and is
  skipped entirely in high contrast; the stroke is 2 pt ink there and the fill is opaque (also under Reduce
  Transparency).
- Pills size to `scale.hitTarget` and `FamiliarType.control(scale)`. The press is a 0.97 squeeze; when motion is
  simplified it is a short dim to 0.8 instead, so Reduce Motion users still see the press.
- `AccentPillStyle` labels use `onOcean`, never a hard-coded white.

## Components
- `StatusChip` never truncates: with no room (accessibility Dynamic Type, severe) the text wraps and the chip grows
  in height. Put chip rows in a `ViewThatFits` or a `VStack` at accessibility sizes if two chips must stay readable.
- `MicMeter` exposes label + value with `.updatesFrequently`; inactive bars are outlines under Differentiate
  Without Color and in high contrast, so the level reads without hue.
- `Monogram(name:size:)`: `size` is the **balanced base diameter**; the monogram multiplies it by `scale.iconScale`
  itself (44 → 66 pt on severe). Derive layout offsets from `size * scale.iconScale`, never pre-scale the argument.
  Letter: fixed-size, dark navy on the pastel pigments; white on the deep high-contrast pigments in light mode.
- `NearbyPersonCard(name:direction:distance:score:actionTitle:action:actionHint:)`: VoiceOver says
  "<name>. <direction>, <distance>. Known person."; `score` is never spoken or shown. Pass `actionHint`
  ("Calls Marcus") or the default "Opens <action> for <name>" is used.
- `PrivacyBanner` is static text (one VoiceOver element, not a heading).
- `AuroraBackground(intensity:mood:)`: still (deterministic frame) under `simplifyMotion`, Reduce Motion and
  `.paused`; the timeline also stops while the scene is not active; 0.55 × intensity in high contrast or under
  Reduce Transparency, 0.7 × in dark mode; hidden from VoiceOver. Requires iOS 18 (`MeshGradient`), which is the
  deployment target.

## How to use
```swift
struct RoomHeader: View {
    @Environment(\.visionScale) private var scale
    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(8)) {
            Eyebrow(text: "In the room")
            Text("Three people").font(FamiliarType.titleXL(scale)).foregroundStyle(FamiliarPalette.ink(scale))
            Image(systemName: "waveform").visionIcon(scale, base: 20)
            Button("Who's here?") { }.buttonStyle(PrimaryPillStyle())      // min height = scale.hitTarget
        }
        .surfaceCard(padding: 16)                                           // base padding; scaled inside
    }
}
ZStack { AuroraBackground(intensity: 0.9, mood: .listening); MimoView() }  // never behind body text
```
Rules: never `Font.system` in screens; every control gets a label and hint; grouped rows are one VoiceOver element;
nothing is colour-only; respect `scale.simplifyMotion` (use `scale.animation(…)`) and `scale.prefersStackedLayout`
for side-by-side rows; keep the aurora behind heroes only; one `MetalFx` control per screen.
