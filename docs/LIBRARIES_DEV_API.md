# libraries.dev SwiftUI kits — verified public API (read from the repo on 2026-10-25)

Package (already in `Familiar.xcodeproj`, pinned to branch `main`): `https://github.com/Jakubantalik/Libraries.dev`.
Products linked to the app target: `BotAvatarsKit`, `ThinkingOrbsKit`, `VoiceGlowKit`. To use `BorderBeamKit`,
`MetalFxKit` (+ its dependency `MagnetKit`) add those product names to the target in `project.pbxproj` exactly like the
three existing `C0FFEE…` entries (PBXBuildFile + Frameworks phase + packageProductDependencies + XCSwiftPackageProductDependency).
All kits: iOS 17+, MIT, Canvas/TimelineView based (Metal shaders only in MetalFxKit and VoiceGlowKit), Reduce Motion aware.
`import BotAvatarsKit`, `import ThinkingOrbsKit`, `import VoiceGlowKit`, `import BorderBeamKit`, `import MetalFxKit`.

## BotAvatarsKit — the living-face avatar (Mimo)
```swift
BotAvatar(type: BotAvatarType = .clover, face: BotAvatarFace? = nil, state: BotAvatarState = .default, size: Double = 64,
          color: BotColor? = nil, ink: BotColor? = nil, brightness: Double = 1, saturation: Double = 1.5, speed: Double = 1,
          paused: Bool = false, seed: Double? = nil, shading: BotAvatarShading = .plastic, shadow: Double = 0.35,
          highlight: Double = 1.3, depth: Double = 0.65, light: Double = 265, rim: Double = 0.5, spread: Double = 1.55,
          interactive: Bool = true, theme: ColorScheme? = nil, whirl: BotAvatarWhirl = .off, jump: BotAvatarJumpConfig = .defaults)
enum BotAvatarType: clover, flower, triangle, square, blob, ghost, circle, drop, star, droid, mech, alien, hexagon, cat, cloud, pill, pebble, puddle
enum BotAvatarFace: eyes, mouth          // mouth adds a small mouth that changes with the state
enum BotAvatarState: `default` (idle: looks around, blinks, occasional hop), working (hopping, smile), sleeping (lids shut, slow breaths)
enum BotAvatarShading: plastic, crisp, smooth, flat
BotColor("#75D9CF")!  BotColor(r:g:b:)  BotColor(Color)   // body colour; `ink` = face colour
```
The view lays out `size` square; a hop is never clipped. `interactive: true` = tap hops, drag makes the eyes follow. `paused`
or system Reduce Motion draws the still pose. Hide it from VoiceOver and provide a text status next to it.

## ThinkingOrbsKit — small animated orbs for AI states
```swift
ThinkingOrb(state: OrbState = .working, size: OrbSize = .px64, theme: OrbTheme = .auto, speed: Double = 1, paused: Bool = false, displaySize: Double? = nil)
enum OrbState: working, searching, solving, listening, connecting, weaving, composing, breathing, shaping   // .label gives a word
enum OrbSize: px64, px20     // `displaySize` renders at any point size while keeping the preset's geometry (vector-crisp)
```

## VoiceGlowKit — a glow that rises with the voice along the bottom edge of a view
```swift
VoiceGlow(type: VoiceGlowType = .standard /* .standard | .pill | .mobile */, meter: VoiceMeter? = nil, level: Double = 0,
          levelProvider: (() -> Double)? = nil, mood: VoiceMood? = nil, motion: (() -> VoiceGlowMotion)? = nil,
          active: Bool = true, colorVariant: VoiceGlowColorVariant = .colorful /* colorful mono ocean sunset forest candy ice gold */,
          theme: VoiceGlowTheme = .auto, cornerRadius: Double = 16, options: VoiceGlowOptions = .init()) { content }
```
Never create a `VoiceMeter` (it opens its own AVAudioEngine and would fight ours): drive it with `levelProvider` from
`coordinator.services?.audioInput.micLevel`. `.mobile` is the phone-screen-bottom preset.

## BorderBeamKit — a soft glow riding a border
```swift
BorderBeam(size: BeamSize = .md /* sm md line pulseOutside pulseInner */, colorVariant: BeamColorVariant = .colorful /* colorful mono ocean sunset … */,
           theme: BeamTheme = .dark /* dark light auto */, staticColors: Bool = false, duration: Double? = nil, active: Bool = true,
           borderRadius: Double? = nil, brightness: Double? = nil, saturation: Double? = nil, hueRange: Double = 30, strength: Double = 1,
           tuning: BeamTuning = .none, onActivate: (() -> Void)? = nil, onDeactivate: (() -> Void)? = nil) { content }
someView.borderBeam(.md, colorVariant: .ocean, theme: .light, active: isListening, borderRadius: 26)   // modifier sugar, same params
```
Use `theme: .auto`/`.light` on our ivory canvas, pass `borderRadius` matching the card, toggle `active` with state (fades in/out).

## MetalFxKit — liquid metal ring around a button or circle, bends with the phone's tilt
```swift
MetalFx(variant: .button /* .button | .circle */, preset: .chromatic /* chromatic silver gold */, theme: .auto, strength: Double = 1,
        shaderScale: Double? = nil, ringWidth: Double? = nil, cornerRadius: Double? = nil, innerShadow: Bool = false, glow: Bool = true,
        glowGain: Double = 1, paused: Bool = false, tilt: Bool = true, source: MetalBendSource = .tilt /* .none .tilt .magnet .pointer .manual(driver) */,
        bendConfig: MetalBendConfig = .default, glowConfig: MetalGlowConfig = .default, fill: Color? = nil, reflection: Double = 1, id: String? = nil) { content }
MetalText("Familiar", font: Font = .system(size: 24, weight: .medium), color: Color = …, preset: .chromatic, …)   // liquid-metal lettering
MetalBadge("New", preset: .chromatic, …)
someView.metalReflection(of: "who-is-here", strength: 0.64, cornerRadius: 26, style: .surface)   // neighbours reflect a ring with that `id`
```
The `.metal` shaders compile through Xcode's build. Keep metal to one hero control per screen (the spec's restraint rule).

## Gotchas
- `Canvas`/`TimelineView` animations do not advance under `ImageRenderer`; snapshots show still frames (fine).
- Nothing here must carry meaning on its own: every effect sits beside text and a VoiceOver label.
- `ThinkingOrb` and `BotAvatar` are `@available(iOS 15/17)`; our deployment target is iOS 18, no guards needed.
