import SwiftUI
import VoiceGlowKit
import BorderBeamKit

/// Full-screen card shown to the other person: Mimo waits respectfully, the question is in large type on a white card
/// whose border glows while Familiar listens, and two huge pills answer it. Tapping is the alternative to saying yes
/// in a loud room. A soft glow at the bottom rises with the microphone level; a burst of particles thanks a yes.
/// The words never shrink: at accessibility text sizes and from the severe profile on, Mimo and the question scroll
/// while the pills stay put at the bottom.
struct ConsentCardView: View {
    let state: ConsentState
    let question: String
    let onAnswer: (Bool) -> Void
    let onCancel: () -> Void
    var levelProvider: (() -> Double)? = nil
    /// Set once they agreed and the wearer handed them the phone: show the number pad instead of YES / NO.
    var numberEntry: SpokenConsentFlow.NumberRequest? = nil
    var userName = ""
    /// The typed number (nil = Skip) and the name as shown, possibly corrected by the person.
    var onNumber: (String?, String) -> Void = { _, _ in }
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var yesBurst = 0
    @State private var number = ""
    @State private var name = ""
    @FocusState private var numberFocused: Bool

    var body: some View {
        if let entry = numberEntry { numberPad(entry) } else { questionScreen }
    }

    /// Once they agreed and the wearer handed them the phone: name (editable) and number, same canvas and pills.
    private func numberPad(_ entry: SpokenConsentFlow.NumberRequest) -> some View {
        VStack(spacing: 18) {
            ScrollView {
                VStack(spacing: 18) {
                    MimoView(state: .success, size: 96, showsGlow: !scale.highContrast)
                    VStack(spacing: 14) {
                        Text("\(entry.name.map { "Thanks, \($0)! " } ?? "Thanks! ")Type your phone number for \(userName.isEmpty ? "the" : "\(userName)'s") contacts.")
                            .font(FamiliarType.title(scale))
                            .foregroundStyle(FamiliarPalette.ink(scale))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        entryField("Your name", text: $name)
                            .textContentType(.givenName)
                            .accessibilityLabel("Your name")
                            .accessibilityHint("Fix the spelling if it is wrong")
                        entryField("Phone number", text: $number)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($numberFocused)
                            .accessibilityLabel("Phone number")
                            .accessibilityHint("Your number is saved only in this phone's contacts")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            let layout: AnyLayout = tall ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))
            layout {
                Button { onNumber(nil, name) } label: { pillText("Skip") }
                    .buttonStyle(GhostPillStyle())
                    .accessibilityHint("Saves the contact without a number")
                Button { FamiliarHaptics.play(.consent); onNumber(number, name) } label: { pillText("Save") }
                    .buttonStyle(AccentPillStyle())
                    .disabled(PhoneNumber.digits(in: number).count < 7)
                    .opacity(PhoneNumber.digits(in: number).count < 7 ? 0.5 : 1)
                    .accessibilityHint("Saves this number with your contact")
            }
        }
        .padding(FamiliarPalette.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familiarCanvas()
        .onAppear { name = entry.name ?? ""; numberFocused = true }
    }

    private func entryField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(FamiliarType.title(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(minHeight: scale.hitTarget * 1.2)
            .background(FamiliarPalette.canvas(scale), in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
    }

    private var questionScreen: some View {
        VoiceGlow(type: .mobile, levelProvider: levelProvider, active: state == .listening, colorVariant: .ocean, cornerRadius: 0) {
            VStack(spacing: 18) {
                cancelRow
                middle
                answers
                Text("Your face stays on this phone. You can be removed any time.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .multilineTextAlignment(.center)
            }
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .familiarCanvas()
    }

    // MARK: - Pieces

    private var cancelRow: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(GhostPillStyle())
                .frame(width: 120 * scale.textScale)
                .accessibilityHint("Stops asking and saves nothing")
        }
    }

    private var tall: Bool { dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout }

    /// Mimo and the question, centred between the cancel row and the pills; scrollable when the type is large.
    @ViewBuilder private var middle: some View {
        if tall {
            ScrollView {
                VStack(spacing: 18) {
                    mimo
                    questionCard
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Spacer(minLength: 0)
            mimo
            questionCard
            Spacer(minLength: 0)
        }
    }

    /// `MimoView` scales `size` by the icon scale itself (capped at 1.2), so the base size is passed unscaled.
    private var mimo: some View {
        MimoView(state: mimoState, size: 110, showsGlow: !scale.highContrast)
    }

    /// The question and the status line on a white card. The border beam rides the edge only while listening.
    private var questionCard: some View {
        VStack(spacing: 12) {
            Text(question)
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            MimoStatusLine(state: mimoState, text: statusLine)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
        .borderBeam(.md, colorVariant: .ocean, theme: .auto, active: state == .listening, borderRadius: 26)
        .accessibilityElement(children: .contain)
    }

    /// No on the left, Yes on the right; stacked at accessibility text sizes. Each pill is twice the hit target tall.
    private var answers: some View {
        let layout: AnyLayout = tall
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Button { answer(false) } label: { pillText("No") }
                .buttonStyle(GhostPillStyle())
                .accessibilityLabel("No, do not remember me")
                .accessibilityHint("Nothing is saved")
            Button { answer(true) } label: { pillText("Yes") }
                .buttonStyle(AccentPillStyle())
                .overlay(ParticleBurst(trigger: yesBurst, color: FamiliarPalette.ocean(scale)).allowsHitTesting(false))
                .accessibilityLabel("Yes, remember me")
                .accessibilityHint("Saves your face on this phone only")
        }
        .disabled(state == .saving)
    }

    private func pillText(_ word: String) -> some View {
        Text(word)
            .font(FamiliarType.display(scale))
            .frame(maxWidth: .infinity, minHeight: scale.hitTarget * 2)
    }

    /// Yes is the rising "they said yes" pattern; No is the plain "accepted" tap, so a decline never feels like a success.
    private func answer(_ yes: Bool) {
        if yes {
            yesBurst += 1
            FamiliarHaptics.play(.consent)
        } else {
            FamiliarHaptics.play(.accepted)
        }
        onAnswer(yes)
    }

    // MARK: - State

    private var mimoState: MimoState { state == .listening ? .listening : .waitingForConsent }

    private var statusLine: String {
        switch state {
        case .asking: return "Asking…"
        case .listening: return "Listening for your answer, or tap"
        case .saving: return "Saving…"
        default: return "Waiting"
        }
    }
}

#Preview("Consent card") {
    ConsentCardView(state: .listening,
                    question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"),
                    onAnswer: { _ in },
                    onCancel: {})
}

#Preview("Consent card · severe") {
    ConsentCardView(state: .listening,
                    question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"),
                    onAnswer: { _ in },
                    onCancel: {})
        .environment(\.visionScale, VisionScale.make(.severe))
}
