import SwiftUI

/// One action of a `GooeyMenu`: a title, a symbol and what happens when it is chosen.
struct GooeyMenuItem: Identifiable {
    let id: UUID
    let title: String
    let systemImage: String
    let action: () -> Void

    init(title: String, systemImage: String, action: @escaping () -> Void) {
        self.id = UUID()
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

/// A round plus button that unfolds its items upward through goo: a `Canvas` draws the button and item circles with
/// `.alphaThreshold` over `.blur`, so the circles merge and stretch like liquid as they separate. The visible items
/// are real `Button`s with text labels laid exactly over the goo, so VoiceOver, Voice Control and Switch Control see
/// ordinary controls. Place it bottom-trailing in an overlay; it closes after an item is chosen, when the plus is
/// tapped again, on a tap in its own empty area, or on the VoiceOver escape gesture. It covers only its own bounds:
/// a caller that wants tap-outside-to-close adds a scrim behind it.
///
/// Under `simplifyMotion` / Reduce Motion the circles stay crisp and the items appear in place with a crossfade (no
/// travel); under high contrast the ink surfaces get a white rim.
struct GooeyMenu: View {
    let systemImage: String
    let items: [GooeyMenuItem]
    /// Spoken name of the plus button ("Add someone").
    var label: String = "Add"

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen: Bool = false

    init(systemImage: String = "plus", items: [GooeyMenuItem]) {
        self.systemImage = systemImage
        self.items = items
    }

    init(systemImage: String = "plus", label: String, items: [GooeyMenuItem]) {
        self.systemImage = systemImage
        self.items = items
        self.label = label
    }

    // MARK: Geometry

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }
    /// The plus button.
    private var mainDiameter: CGFloat { scale.hitTarget + 8 }
    /// Each item circle.
    private var itemDiameter: CGFloat { scale.hitTarget }
    private var gap: CGFloat { 10 }
    private var step: CGFloat { itemDiameter + gap }
    private var inset: CGFloat { 12 }
    private var gooWidth: CGFloat { mainDiameter + inset * 2 }
    private var gooHeight: CGFloat { mainDiameter + inset * 2 + CGFloat(items.count) * step }

    /// Vertical travel of item `index` from the plus button's centre when open (negative = up).
    private func rise(_ index: Int) -> CGFloat {
        -(mainDiameter / 2 + gap + itemDiameter / 2 + CGFloat(index) * step)
    }

    private func itemAnimation(_ index: Int) -> Animation {
        let delay = Double(isOpen ? index : (items.count - 1 - index)) * FamiliarMotion.stagger
        return FamiliarMotion.reduced(animates).delay(delay)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            goo
            if isOpen { closeArea }
            ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                itemRow(pair.element, index: pair.offset)
            }
            mainButton
        }
        .frame(height: gooHeight, alignment: .bottomTrailing)
        .animation(FamiliarMotion.reduced(animates), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { if isOpen { toggle() } }
    }

    /// While open, a tap on the menu's own empty area (between and beside the rows) closes it.
    private var closeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .accessibilityHidden(true)
    }

    // MARK: Goo

    /// Every symbol is the full size of the canvas with its circle sitting at the plus button's centre, so an
    /// animated `.offset` never leaves the symbol's bounds; the canvas draws each symbol at its own centre.
    private var goo: some View {
        Canvas(rendersAsynchronously: false) { graphics, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            graphics.addFilter(.alphaThreshold(min: 0.5, color: FamiliarPalette.ink(scale)))
            graphics.addFilter(.blur(radius: animates ? 11 : 0))
            graphics.drawLayer { layer in
                if let main = graphics.resolveSymbol(id: 0) {
                    layer.draw(main, at: centre)
                }
                for index in items.indices {
                    if let circle = graphics.resolveSymbol(id: index + 1) {
                        layer.draw(circle, at: centre)
                    }
                }
            }
        } symbols: {
            gooSymbol(diameter: mainDiameter, offsetY: 0)
                .tag(0)
            ForEach(Array(items.indices), id: \.self) { index in
                gooSymbol(diameter: itemDiameter, offsetY: isOpen ? rise(index) : 0)
                    .animation(animates ? itemAnimation(index) : nil, value: isOpen)
                    .tag(index + 1)
            }
        }
        .frame(width: gooWidth, height: gooHeight)
        .overlay { if scale.highContrast { highContrastRims } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A black circle anchored at the plus button's centre inside a canvas-sized frame.
    private func gooSymbol(diameter: CGFloat, offsetY: CGFloat) -> some View {
        Circle()
            .fill(Color.black)
            .frame(width: diameter, height: diameter)
            .offset(y: offsetY)
            .padding(.bottom, inset + (mainDiameter - diameter) / 2)
            .frame(width: gooWidth, height: gooHeight, alignment: .bottom)
    }

    /// Under high contrast each ink circle gets a 2 pt white rim so it separates from a dark card beneath.
    /// The rims snap into place under reduced motion (only their opacity crossfades).
    private var highContrastRims: some View {
        ZStack(alignment: .center) {
            Circle()
                .strokeBorder(FamiliarPalette.canvas(scale), lineWidth: 2)
                .frame(width: mainDiameter, height: mainDiameter)
            ForEach(Array(items.indices), id: \.self) { index in
                Circle()
                    .strokeBorder(FamiliarPalette.canvas(scale), lineWidth: 2)
                    .frame(width: itemDiameter, height: itemDiameter)
                    .frame(width: mainDiameter, height: mainDiameter)
                    .offset(y: isOpen ? rise(index) : 0)
                    .transaction { transaction in if !animates { transaction.animation = nil } }
                    .opacity(isOpen ? 1 : 0)
            }
        }
        .padding(.bottom, inset)
        .frame(width: gooWidth, height: gooHeight, alignment: .bottom)
    }

    // MARK: Items

    /// A labelled button over each goo circle. The title wraps instead of truncating and the row grows with it; the
    /// `.transaction` after the offset makes the row appear in place under reduced motion while its opacity fades.
    private func itemRow(_ item: GooeyMenuItem, index: Int) -> some View {
        Button {
            choose(item)
        } label: {
            HStack(spacing: 12) {
                Text(item.title)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(FamiliarPalette.surface(scale), in: Capsule())
                    .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.highContrast ? 2 : 1))
                    .shadow(color: Color.black.opacity(scale.highContrast ? 0 : 0.06), radius: 10, y: 4)
                Image(systemName: item.systemImage)
                    .visionIcon(scale, base: 20)
                    .foregroundStyle(FamiliarPalette.canvas(scale))
                    .frame(width: itemDiameter, height: itemDiameter)
                    .frame(width: mainDiameter, height: mainDiameter)
            }
            .frame(minHeight: mainDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(GooeyItemPressStyle(animates: animates))
        .padding(.trailing, inset)
        .padding(.bottom, inset)
        .offset(y: isOpen ? rise(index) : 0)
        .transaction { transaction in if !animates { transaction.animation = nil } }
        .opacity(isOpen ? 1 : 0)
        .animation(itemAnimation(index), value: isOpen)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .accessibilityLabel(item.title)
    }

    // MARK: Plus button

    private var mainButton: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: systemImage)
                .visionIcon(scale, base: 26)
                .foregroundStyle(FamiliarPalette.canvas(scale))
                .rotationEffect(.degrees(isOpen && animates ? 45 : 0))
                .frame(width: mainDiameter, height: mainDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(GooeyItemPressStyle(animates: animates))
        .padding(.trailing, inset)
        .padding(.bottom, inset)
        .accessibilityLabel(label)
        .accessibilityValue(isOpen ? "Open" : "Closed")
        .accessibilityHint(isOpen ? "Closes the menu" : "Opens \(items.count) \(items.count == 1 ? "option" : "options")")
        .accessibilityAddTraits(.isButton)
    }

    /// Opening is a command accepted (one light tap); closing is silent, so the "paused" pattern keeps its meaning.
    private func toggle() {
        withAnimation(FamiliarMotion.reduced(animates)) { isOpen.toggle() }
        if isOpen { FamiliarHaptics.play(.accepted) }
    }

    private func choose(_ item: GooeyMenuItem) {
        withAnimation(FamiliarMotion.reduced(animates)) { isOpen = false }
        FamiliarHaptics.play(.accepted)
        item.action()
    }
}

/// 0.97 press scale for the goo buttons; nothing moves under reduced motion.
private struct GooeyItemPressStyle: ButtonStyle {
    let animates: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && animates ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

// MARK: - Previews

private struct GooeyMenuPreview: View {
    @Environment(\.visionScale) private var scale
    @State private var lastChoice: String = "Nothing chosen yet"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("People").font(FamiliarType.titleXL(scale)).foregroundStyle(FamiliarPalette.ink(scale))
                Text(lastChoice).font(FamiliarType.body(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale))
                Spacer()
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            GooeyMenu(systemImage: "plus", label: "Add someone", items: [
                GooeyMenuItem(title: "Ask them out loud", systemImage: "waveform") { lastChoice = "Ask them out loud" },
                GooeyMenuItem(title: "Show invitation", systemImage: "qrcode") { lastChoice = "Show invitation (coming later)" },
            ])
            .padding(.trailing, FamiliarPalette.margin - 12)
            .padding(.bottom, 24)
        }
        .familiarCanvas()
    }
}

#Preview("Gooey menu") {
    GooeyMenuPreview()
}

#Preview("Gooey menu · severe") {
    GooeyMenuPreview()
        .environment(\.visionScale, VisionScale.make(.severe))
}
