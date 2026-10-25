import SwiftUI

/// "Show invitation": the tap-to-join page for the other person's phone is coming later. Until then this sheet
/// explains the spoken-consent path that works today, and offers to start it. No fake QR code, no fake link.
struct InvitationSheet: View {
    /// The wearer's first name, used to quote the exact question Familiar asks the other person.
    let userName: String
    /// Starts the consent flow (the same path as Today and the volume button); the sheet dismisses itself afterwards.
    let onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Coming later")
                    Text("Show invitation")
                        .font(FamiliarType.titleXL(scale))
                        .foregroundStyle(FamiliarPalette.ink(scale))
                        .accessibilityAddTraits(.isHeader)
                    Text("A tap-to-join page, where someone opens a link on their own phone and chooses to be remembered, is coming later. Today the other person agrees out loud, and that works right now.")
                        .font(FamiliarType.body(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }

                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "How spoken consent works")
                    InvitationStep(number: 1, title: "You ask", detail: "Say “Familiar, remember them”, press the volume button, or tap Ask them out loud.")
                    InvitationStep(number: 2, title: "Familiar asks them", detail: "“\(Phrasebook.consentQuestion(userName: userName, name: nil))”")
                    InvitationStep(number: 3, title: "They decide", detail: "They say yes, or tap Yes on your phone. A no saves nothing.")
                    InvitationStep(number: 4, title: "Saved on this phone", detail: "Their face, the few seconds of their yes and a contact card stay here. Only text ever leaves the phone.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()

                Text("A stranger is always “a person”. Nothing is stored before they agree, and anyone can be removed later.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .padding(.horizontal, 4)

                VStack(spacing: 12) {
                    Button { onAsk(); dismiss() } label: { Label("Ask them out loud", systemImage: "waveform") }
                        .buttonStyle(PrimaryPillStyle())
                        .accessibilityHint("Starts the spoken consent flow with the person in front of you")
                    Button { dismiss() } label: { Text("Not now") }
                        .buttonStyle(GhostPillStyle())
                        .accessibilityHint("Closes this sheet")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 20)
        }
        .familiarCanvas()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One numbered step: ocean numeral in a ring, title, detail. One VoiceOver element. The ring follows the numeral's
/// text size (Dynamic Type and the profile's text scale) so the digit never spills past the stroke.
private struct InvitationStep: View {
    let number: Int
    let title: String
    let detail: String
    @Environment(\.visionScale) private var scale
    @ScaledMetric(relativeTo: .footnote) private var ringBase: CGFloat = 28

    private var ringSide: CGFloat { ringBase * scale.textScale }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.ocean(scale))
                .lineLimit(1)
                .frame(width: ringSide, height: ringSide)
                .overlay(Circle().strokeBorder(FamiliarPalette.ocean(scale), lineWidth: scale.highContrast ? 2 : 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                Text(detail)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}

#Preview("Invitation sheet") {
    InvitationSheet(userName: "Priya", onAsk: {})
}
