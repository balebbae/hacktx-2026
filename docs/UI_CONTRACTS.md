# Familiar UI build — contracts, ownership and rules for the parallel design sessions (branch `sahas`)

Read `AGENTS.md` (product rules, Swift contracts), `docs/DESIGN_SPEC.md` (the visual spec) and `docs/LIBRARIES_DEV_API.md`.
The app already runs end to end on `main`; this pass makes it beautiful, accessible and complete. Every screen keeps the
existing wiring: `AppState`, `AppCoordinator`, `FlowRuntime`, `Services`, `Phrasebook`, `Secrets`, `UserSettings` keys.

## Motto and voice
App name **Familiar**. Motto: **"The finer things in life are felt, not seen."** Tagline for onboarding: **"Because everyone
deserves to feel seen."** Pitch lines to reuse on screens and in the demo: "The hardest part of navigating a room isn't
always finding the door. Sometimes, it's finding your place in the conversation." / "We're not helping people identify
faces. We're helping them recognize opportunities, build relationships, and experience belonging." / "We're not replacing
human connection with artificial intelligence. We're using artificial intelligence to make human connection more accessible."
Copy is invitational and precise: sentence case, no exclamation marks, never "scan", "detect faces", "surveillance".

## Typography — Plus Jakarta Sans everywhere
Font files are bundled and registered: `PlusJakartaSans-Regular/Medium/SemiBold/Bold.ttf` (PostScript names
`PlusJakartaSans-Regular`, `-Medium`, `-SemiBold`, `-Bold`). **Default weight is SemiBold (600) for every label**; Regular
only for long body paragraphs; Bold only for the display headline. Always go through `FamiliarType` (below) so the vision
profile scales everything; never `Font.system` in screens. Use `relativeTo:` so Dynamic Type still applies.

## Vision profile — one preference, not a diagnosis (owned by the DesignSystem session, consumed by everyone)
```swift
enum VisionProfile: String, CaseIterable, Codable, Identifiable { case balanced, lowVision, severe, nonVisual
    var id: String { rawValue }; var title: String; var detail: String }        // "Balanced", "Low vision", "Severe", "Non-visual"
struct VisionScale: Equatable {
    let textScale: CGFloat      // balanced 1.0 · lowVision 1.25 · severe 1.6 · nonVisual 1.0 (VoiceOver users, keep layout sane)
    let iconScale: CGFloat      // 1.0 · 1.2 · 1.5 · 1.0
    let weight: Font.Weight     // .semibold · .semibold · .bold · .semibold
    let hitTarget: CGFloat      // 52 · 60 · 72 · 60
    let highContrast: Bool      // false · true · true · false  (opaque surfaces, 2 pt strokes, no translucency, ink on white)
    let simplifyMotion: Bool    // false · false · true · true  (also true when the system Reduce Motion is on)
    let spokenFirst: Bool       // false · false · false · true (VoiceOver summaries first, visuals secondary)
    static func make(_ p: VisionProfile) -> VisionScale
}
extension EnvironmentValues { var visionScale: VisionScale }   // default .make(.balanced); set at the root from AppState.visionProfile
extension AppState { @Published var visionProfile: VisionProfile }   // persisted in UserDefaults key "visionProfile"
enum FamiliarFont { static func jakarta(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> Font }
enum FamiliarType {   // every size already multiplied by `scale.textScale`; weight from `scale.weight` unless noted
    static func display(_ s: VisionScale) -> Font     // 40 bold
    static func titleXL(_ s: VisionScale) -> Font     // 32
    static func title(_ s: VisionScale) -> Font       // 24
    static func body(_ s: VisionScale) -> Font        // 17
    static func supporting(_ s: VisionScale) -> Font  // 15 (medium)
    static func micro(_ s: VisionScale) -> Font       // 13
    static func companion(_ s: VisionScale) -> Font   // 20, Mimo's own lines
    static func mono(_ s: VisionScale) -> Font        // 13 monospaced digits for timestamps only
}
extension View { func visionIcon(_ s: VisionScale, base: CGFloat = 20) -> some View }   // sets icon font size × iconScale
```
`FamiliarPalette` stays as it is (`canvas, canvasSecondary, surface, ink, inkSecondary, stroke, ocean, lilac, mint, peach,
success, warning, danger`) plus `static func stroke(_ s: VisionScale) -> Color` (stronger in high contrast) and
`static func surface(_ s: VisionScale) -> Color` (always opaque in high contrast).
Pill styles stay: `PrimaryPillStyle`, `AccentPillStyle`, `GhostPillStyle`; they must read `visionScale` for height and font.
`AuroraBackground(intensity: Double = 1, mood: AuroraMood = .calm)` — the shifting blue→orange→purple mesh gradient (the
wallet reference): `MeshGradient` animated by `TimelineView`, frozen under `simplifyMotion`/Reduce Motion, never behind body text.

## Motion library (owned by the Motion session, `Familiar/UI/Motion/`), consumed by everyone — exact signatures
```swift
struct GlassEdgePager<Content: View>: View { init(@ViewBuilder content: () -> Content) }
   // horizontal paging ScrollView; each page is a child; pages blur + fade + scale into glass at the edges while swiping
   // (scrollTransition on iOS 17; `.glassEffect` edge strips on iOS 26 behind `if #available`); honors simplifyMotion
struct CueToast: View { init(text: String, systemImage: String, tint: Color) }      // rises with fade+blur+scale; caller dismisses after 4–6 s
struct ShimmerText: View { init(_ text: String, font: Font, color: Color) }         // masked gradient sweep ("Thinking…")
struct NumberPop: View { init(value: Int, font: Font, color: Color) }                // digits flip with blur and stagger
struct ParticleBurst: View { init(trigger: Int, color: Color) }                     // like-button burst, 600 ms, Reduce Motion → none
struct SlidingPillSegment<T: Hashable>: View { init(options: [(T, String)], selection: Binding<T>) }  // pill indicator follows selection
struct GooeyMenu: View { init(systemImage: String = "plus", items: [GooeyMenuItem]) }  // gooey plus menu: Canvas alphaThreshold + blur
struct GooeyMenuItem: Identifiable { let id: UUID; let title: String; let systemImage: String; let action: () -> Void; init(title:systemImage:action:) }
extension View {
    func errorShake(trigger: Int) -> some View
    func skeletonReveal(isLoaded: Bool) -> some View
    func liftOnPress() -> some View                        // 0.97 scale for 100 ms (spec)
    func cardResize() -> some View                         // smooth size animation for cards whose content changes
}
enum HapticKind { case listen, accepted, cue, left, consent, paused, error }
enum FamiliarHaptics { static func play(_ kind: HapticKind) }   // CoreHaptics patterns, no-op when unsupported or disabled in settings (UserDefaults "hapticsEnabled", default true)
```
All motion uses `.spring(response: 0.44, dampingFraction: 0.78)` for small Mimo-like moves and `.easeInOut` for diffusion.

## Screens and ownership (one session per row; never edit another row's files)
| Session | Owns | Builds |
|---|---|---|
| DesignSystem | `Familiar/UI/Design/*`, `Familiar/App/AppState.swift`, `docs/DESIGN_SYSTEM.md` | VisionProfile + VisionScale + environment, FamiliarFont/FamiliarType (Jakarta), palette helpers, pill styles reading the scale, `AuroraBackground`, `StatusChip`, `MicMeter`, `CueTicker`, `PrivacyBanner`, `Monogram`, `NearbyPersonCard`, `Eyebrow`, `SurfaceCard` (all existing components kept and scaled) |
| Motion | `Familiar/UI/Motion/*` | Everything in the motion library above, with `#Preview`s |
| Onboarding | `Familiar/UI/Onboarding/*`, `Familiar/App/FamiliarApp.swift`, `Familiar/App/ReadinessView.swift` | Welcome (Mimo + "Because everyone deserves to feel seen." + motto), What Familiar can and cannot do (3 cards), "How would you like Familiar to communicate?" (VisionProfile picker with live preview of text size + a sample spoken cue via `coordinator.services?.speaker`), Privacy promise (3 lines), Readiness restyle, Connect glasses / Continue with phone (wraps `GlassesRegistrationView`). Pages in `GlassEdgePager`. `RootView` shows onboarding until `@AppStorage("onboardingDone")` |
| TodayRoom | `Familiar/UI/HomeView.swift`, `Familiar/UI/JudgeView.swift`, `Familiar/UI/Room/*`, `Familiar/UI/Mimo/*` | Today hero (Mimo, aurora, headline, "Who's here?" as the one `MetalFx` button, Pause / Remember them, cue-level `SlidingPillSegment`, nearby card with `borderBeam` while a cue is fresh), Room (cards + **RoomRadarView**: the spatial map — a half-circle with five bands ahead/left/right/far left/far right and three distance rings, known people as named dots, unknown as unlabeled dots, one VoiceOver summary), camera stage, diagnostics folded; Mimo lumen ripple on a fresh cue |
| People | `Familiar/UI/PeopleView.swift`, `Familiar/UI/People/*` | People list as cards (monogram/photo, name, met where/when, "Opted in"), search, filter chips All / Recent, **Add someone** via `GooeyMenu` (Ask them out loud → consent flow; Show invitation → explains the tag flow is coming), Person detail (hero, Call / Text / Where we met / Remove with confirmation), **PlacesMapView** (MapKit map of where people were met, from `Person.met`; one annotation per person; VoiceOver list under the map) |
| YouSettings | `Familiar/UI/SettingsView.swift`, `Familiar/UI/MainTabView.swift`, `Familiar/UI/You/*`, `Familiar/UI/DemoControlsView.swift`, `Familiar/UI/ConsentCardView.swift` | You hub, Accessibility settings (vision profile, text preview, haptics toggle, speech rate/volume via `UserDefaults` keys `speechRate`, `speechVolume`, "Preview my settings" plays a sample cue), Voice & cues (existing settings restyled), Privacy dashboard ("Your people. Your control.": counts, Remove everyone, data explanation), Demo controls restyled, consent card with `borderBeam` while listening and `ParticleBurst` on yes, `CueToast` shown from `MainTabView` for 5 s on each new utterance |

Shared files nobody edits in this pass: `Familiar/Core/*`, `Familiar/App/AppCoordinator.swift`, `Familiar/App/Services.swift`,
`Familiar/App/Secrets.swift`, `Familiar/App/GlassesRegistrationView.swift`, everything outside `Familiar/UI` and `Familiar/App`,
`Familiar.xcodeproj/*` (except the YouSettings session may add `BorderBeamKit`/`MetalFxKit`/`MagnetKit` product entries to the
project, mirroring the existing `C0FFEE…` entries; the TodayRoom session needs them, so YouSettings does this first thing).

## Rules every session follows
1. Accessibility is the product: every control has a label and hint; grouped rows are one VoiceOver element; nothing is
   colour-only; `Dynamic Type` works to accessibility sizes (no fixed-height clipping); `Reduce Motion`, `Reduce Transparency`,
   `Increase Contrast`, `Differentiate Without Color` respected; focus never jumps; announcements rate-limited.
2. Read `visionScale` from the environment in every screen and size text, icons and hit targets with it.
3. Keep the existing behaviour: same actions call the same `runtime`/`coordinator` methods; do not invent new services.
4. No fake controls: a button navigates, changes state, or says "Coming later".
5. Only text leaves the phone; strangers are "a person"; never describe mood or intent.
6. Build for compile-correctness without Xcode: plain SwiftUI APIs from iOS 17/18 (guard iOS 26 with `if #available`),
   explicit types where inference is deep, no trailing-closure ambiguity, `@ViewBuilder` where needed. Run
   `xcrun swiftc -parse` on every file you write (the Mac has the Swift 6 parser, not the iOS SDK).
7. Add a `#Preview` to every new view. Add or update `FamiliarTests/SnapshotRenderTests.swift` only in the YouSettings session.
8. Report back a list of files, public symbols you added, symbols you consumed from other sessions, and anything uncertain.
