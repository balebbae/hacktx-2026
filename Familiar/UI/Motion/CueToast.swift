import SwiftUI

/// The visual twin of a spoken cue: a white pill that rises from below with fade, blur and a little scale, then
/// leaves the same way. The caller shows it with `if let cue { CueToast(...) }` inside `withAnimation(CueToast.spring())`
/// and removes it after 4–6 s; the toast only draws, it never speaks (the `Speaker` already did). A toast pinned to the
/// top of the screen can drop in instead: `CueToast(text:systemImage:tint:edge: .top)`.
///
/// Under `simplifyMotion` or Reduce Motion it crossfades. Under high contrast the surface is opaque with a 2 pt stroke.
struct CueToast: View {
    let text: String
    let systemImage: String
    let tint: Color
    /// The edge the toast enters from: `.bottom` rises into place, `.top` drops in.
    var edge: Edge = .bottom

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: String, systemImage: String, tint: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    init(text: String, systemImage: String, tint: Color, edge: Edge) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.edge = edge
    }

    /// A toast with one small action pill at its trailing end ("Repeat" on a spoken cue). The action is also exposed
    /// to VoiceOver as a custom action named `actionTitle`, so the toast stays one element.
    init(text: String, systemImage: String, tint: Color, edge: Edge, actionTitle: String?, actionHint: String? = nil, action: (() -> Void)?) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.edge = edge
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.action = action
    }

    /// Optional trailing action (spec 20.5 §06 "Repeat cue").
    private var actionTitle: String? = nil
    private var actionHint: String? = nil
    private var action: (() -> Void)? = nil

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }
    private var iconWell: CGFloat { 36 * scale.iconScale }
    private var radius: CGFloat { scale.hitTarget / 2 }
    private var hasAction: Bool { actionTitle != nil && action != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .visionIcon(scale, base: 17)
                .foregroundStyle(tint)
                .frame(width: iconWell, height: iconWell)
                .background(tint.opacity(scale.highContrast ? 0.22 : 0.14), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let actionTitle, let action {
                Spacer(minLength: 4)
                Button(actionTitle, action: action)
                    .buttonStyle(CueToastActionStyle())
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, hasAction ? 10 : 20)
        .padding(.vertical, 8)
        .frame(minHeight: scale.hitTarget)
        .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.highContrast ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(scale.highContrast ? 0 : 0.08), radius: 18, y: 8)
        .transition(CueToast.transition(simplify: !animates, edge: edge))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
        .modifier(CueToastNamedAction(title: actionTitle, hint: actionHint, action: action))
    }

    // MARK: Motion

    /// The spring to wrap the caller's `withAnimation` in when showing or hiding the toast.
    static func spring() -> Animation { FamiliarMotion.spring }

    /// Rise in (move from `edge` + fade + blur + scale), settle out (fade + blur + a smaller scale). Opacity only when
    /// simplified. `.bottom` rises; pass `.top` for a toast pinned under the status bar so it drops into place.
    static func transition(simplify: Bool, edge: Edge = .bottom) -> AnyTransition {
        if simplify { return .opacity }
        let insertion: AnyTransition = .move(edge: edge)
            .combined(with: .opacity)
            .combined(with: AnyTransition(CueToastVeil(scale: 0.92, blur: 10)))
        let removal: AnyTransition = .opacity
            .combined(with: AnyTransition(CueToastVeil(scale: 0.97, blur: 6)))
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

/// Blur + scale that resolves to identity; combined with `.move` and `.opacity` it is the toast's rise.
private struct CueToastVeil: Transition {
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : scale)
            .blur(radius: phase.isIdentity ? 0 : blur)
    }
}

/// The small pill for a toast's one action: micro type, a canvas-tinted capsule, a 44 pt target inside the toast.
/// The word is never truncated; at large sizes the toast's text column yields instead.
private struct CueToastActionStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.micro(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, scale.spacing(12))
            .padding(.vertical, scale.spacing(8))
            .background(FamiliarPalette.canvasSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && FamiliarMotion.animates(scale, reduceMotion: reduceMotion) ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

/// Exposes the toast's action to VoiceOver as a named custom action when there is one; otherwise leaves the view alone.
private struct CueToastNamedAction: ViewModifier {
    let title: String?
    let hint: String?
    let action: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title, let action {
            if let hint {
                content
                    .accessibilityAction(named: Text(title), action)
                    .accessibilityHint(hint)
            } else {
                content
                    .accessibilityAction(named: Text(title), action)
            }
        } else {
            content
        }
    }
}

// MARK: - Convenience host

/// Shows one `CueToast` above `content`, bottom-aligned, with the rise transition and a timed dismissal.
/// `message` is cleared `seconds` after it was set; a new message restarts the timer.
struct CueToastHost<Content: View>: View {
    @Binding var message: CueToastMessage?
    var seconds: Double = 5
    @ViewBuilder let content: () -> Content

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var generation: Int = 0

    var body: some View {
        content()
            .overlay(alignment: .bottom) {
                if let message {
                    CueToast(text: message.text, systemImage: message.systemImage, tint: message.tint)
                        .padding(.horizontal, FamiliarPalette.margin)
                        .padding(.bottom, 12)
                        .id(message.id)
                }
            }
            .onChange(of: message?.id) { _, newID in
                guard newID != nil else { return }
                generation += 1
                let expected = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    guard expected == generation else { return }
                    withAnimation(FamiliarMotion.reduced(FamiliarMotion.animates(scale, reduceMotion: reduceMotion))) {
                        message = nil
                    }
                }
            }
    }
}

/// What a `CueToastHost` shows. Each new message has its own id so a repeated cue still re-animates.
struct CueToastMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let systemImage: String
    let tint: Color

    init(text: String, systemImage: String = "quote.bubble", tint: Color = FamiliarPalette.ocean) {
        self.id = UUID()
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }
}

// MARK: - Previews

#Preview("Cue toast") {
    VStack(spacing: 14) {
        CueToast(text: "Marcus, ahead, close.", systemImage: "person.wave.2", tint: FamiliarPalette.ocean)
        CueToast(text: "Maya left.", systemImage: "arrow.turn.up.left", tint: FamiliarPalette.inkSecondary)
        CueToast(text: "Saved. Marcus is in your contacts.", systemImage: "checkmark.seal", tint: FamiliarPalette.success)
        CueToast(text: "Awareness paused.", systemImage: "pause", tint: FamiliarPalette.warning)
    }
    .padding(FamiliarPalette.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .familiarCanvas()
}

#Preview("Cue toast · severe profile") {
    VStack(spacing: 14) {
        CueToast(text: "Marcus, ahead, close.", systemImage: "person.wave.2", tint: FamiliarPalette.ocean)
        CueToast(text: "Two other people.", systemImage: "person.2", tint: FamiliarPalette.inkSecondary)
    }
    .padding(FamiliarPalette.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .familiarCanvas()
    .environment(\.visionScale, VisionScale.make(.severe))
}

#Preview("Toast host") {
    struct Host: View {
        @State private var message: CueToastMessage?
        var body: some View {
            CueToastHost(message: $message, seconds: 4) {
                VStack {
                    Spacer()
                    Button("Show a cue") {
                        withAnimation(CueToast.spring()) {
                            message = CueToastMessage(text: "Marcus, coming from your right.", systemImage: "person.wave.2")
                        }
                    }
                    .buttonStyle(PrimaryPillStyle())
                    .padding(FamiliarPalette.margin)
                    .padding(.bottom, 80)
                }
            }
            .familiarCanvas()
        }
    }
    return Host()
}
