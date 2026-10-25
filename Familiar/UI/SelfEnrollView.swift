import SwiftUI
import BorderBeamKit

/// Full-screen flow for a sighted stranger holding the phone: intro → front camera scan → name → consent → done.
/// Same canvas, Mimo and pills as the consent card; every control labelled; the wearer only hears the heads-up and the result.
struct SelfEnrollView: View {
    @ObservedObject var model: SelfEnrollModel
    let onClose: () -> Void
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool
    @State private var yesBurst = 0

    var body: some View {
        VStack(spacing: 18) {
            header
            ScrollView {
                VStack(spacing: 18) { content }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(FamiliarPalette.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familiarCanvas()
        .onAppear { model.open() }
        .animation(scale.simplifyMotion ? nil : .easeInOut(duration: 0.3), value: model.step)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Eyebrow(text: stepTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            switch model.step {
            case .done, .cancelled, .saving: EmptyView()
            default:
                Button("Cancel", role: .cancel) { Task { await model.cancel(); onClose() } }
                    .buttonStyle(GhostPillStyle())
                    .frame(width: 120 * scale.textScale)
                    .accessibilityHint("Stops and saves nothing")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .intro:
            MimoView(state: .waitingForConsent, size: 120, showsGlow: !scale.highContrast)
            card {
                bigText(model.introText)
                supporting("You will see yourself on the camera, type your name, then tap Yes or No. Your face never leaves this phone.")
            }
        case .scanning:
            scanPreview
            card {
                bigText(model.hint)
                    .accessibilityLabel("Scanning. \(model.hint)")
                if let err = model.error {
                    Text(err)
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.danger)
                        .accessibilityLabel("Camera problem: \(err)")
                }
            }
        case .name:
            MimoView(state: .listening, size: 96, showsGlow: !scale.highContrast)
            card {
                bigText("What should \(model.userName) call you?")
                field("Your first name", text: $model.name)
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .focused($nameFocused)
                    .onSubmit { model.submitName() }
                    .accessibilityLabel("Your first name")
                    .accessibilityHint("Used when the wearer is told you are nearby")
                field("Phone (optional)", text: $model.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityHint("Saved to the contact so they can call or text you")
                supporting("Only your name is said out loud. Nothing is saved yet.")
            }
        case .consent, .saving:
            MimoView(state: model.step == .saving ? .thinking : .waitingForConsent, size: 110, showsGlow: !scale.highContrast)
            card(beam: model.step == .consent) {
                bigText(model.consentText)
                    .accessibilityAddTraits(.isHeader)
                MimoStatusLine(state: model.step == .saving ? .thinking : .waitingForConsent,
                               text: model.step == .saving ? "Saving…" : "Tap your answer")
                if let err = model.error {
                    Text(err).font(FamiliarType.supporting(scale)).foregroundStyle(FamiliarPalette.danger)
                }
            }
        case .done:
            MimoView(state: .success, size: 120, showsGlow: !scale.highContrast)
            card {
                bigText(model.doneText)
                supporting("\(model.userName) will hear your name when you walk up. You can be removed at any time from People.")
            }
        case .cancelled:
            MimoView(state: .idle, size: 110, showsGlow: !scale.highContrast)
            card { bigText("Nothing saved. Hand the phone back.") }
        }
    }

    private var scanPreview: some View {
        let side = min(280, 240 * scale.iconScale)
        return ZStack {
            if let img = model.preview {
                Image(decorative: img, scale: 1)
                    .resizable().scaledToFill()
                    .scaleEffect(x: model.mirrorsPreview ? -1 : 1, y: 1)
            } else {
                FamiliarPalette.surface(scale)
                Image(systemName: "camera")
                    .font(.system(size: 44 * scale.iconScale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(FamiliarPalette.ocean(scale), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera preview, \(model.collected) of \(model.config.targetEmbeddings) face samples")
    }

    @ViewBuilder private var footer: some View {
        switch model.step {
        case .intro:
            VStack(spacing: 12) {
                Button { Task { await model.beginScan() } } label: {
                    Label("Yes, scan my face", systemImage: "camera.viewfinder")
                }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Turns on the front camera for a few seconds")
                Button("No thanks") { Task { await model.cancel(); onClose() } }
                    .buttonStyle(GhostPillStyle())
                    .accessibilityHint("Closes this screen and saves nothing")
            }
        case .scanning:
            Button { model.finishScan() } label: { Label("Next", systemImage: "arrow.right") }
                .buttonStyle(PrimaryPillStyle())
                .disabled(!model.canContinueScan)
                .opacity(model.canContinueScan ? 1 : 0.5)
                .accessibilityHint(model.canContinueScan ? "Go on to your name" : "Enabled once enough face samples are collected")
        case .name:
            Button { model.submitName() } label: { Label("Next", systemImage: "arrow.right") }
                .buttonStyle(PrimaryPillStyle())
                .disabled(!model.canSubmitName)
                .opacity(model.canSubmitName ? 1 : 0.5)
                .accessibilityHint("Shows the permission question")
        case .consent, .saving:
            VStack(spacing: 12) {
                answers
                supporting("Faces stay on this phone. You can be removed any time.")
            }
        case .done, .cancelled:
            Button { Task { await model.close(); onClose() } } label: { Label("Done", systemImage: "hand.raised") }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Closes this screen")
        }
    }

    private var answers: some View {
        let layout: AnyLayout = (dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout)
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
        .disabled(model.step == .saving)
    }

    private func answer(_ yes: Bool) {
        if yes { yesBurst += 1; FamiliarHaptics.play(.consent) } else { FamiliarHaptics.play(.accepted) }
        Task { await model.answer(yes: yes); if !yes { onClose() } }
    }

    // MARK: - Pieces

    private func card<C: View>(beam: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
            .borderBeam(.md, colorVariant: .ocean, theme: .auto, active: beam, borderRadius: 26)
            .accessibilityElement(children: .contain)
    }

    private func bigText(_ s: String) -> some View {
        Text(s)
            .font(FamiliarType.title(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func supporting(_ s: String) -> some View {
        Text(s)
            .font(FamiliarType.supporting(scale))
            .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(FamiliarType.body(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .padding(.horizontal, 18)
            .frame(minHeight: scale.hitTarget)
            .background(FamiliarPalette.canvas(scale), in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
    }

    private func pillText(_ word: String) -> some View {
        Text(word)
            .font(FamiliarType.display(scale))
            .frame(maxWidth: .infinity, minHeight: scale.hitTarget * 2)
    }

    private var stepTitle: String {
        switch model.step {
        case .intro: return "Introduce yourself"
        case .scanning: return "Step 1 of 3 · Face"
        case .name: return "Step 2 of 3 · Name"
        case .consent, .saving: return "Step 3 of 3 · Permission"
        case .done: return "Saved"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Builds the model from the live services. Camera: front phone camera, or the `enroll_marcus` fixture in the Simulator
/// / when `UserSettings.selfEnrollUseFixture` is on. Perception: a second `PerceptionPipeline` sharing the live
/// embedder (never a fork of the perception code); `ScriptedPerception` when the app runs scripted.
enum SelfEnrollFactory {
    static var useFixtureDefault: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var useFixture: Bool {
        UserDefaults.standard.object(forKey: UserSettings.selfEnrollUseFixture) as? Bool ?? useFixtureDefault
    }

    @MainActor
    static func preview() -> SelfEnrollModel {
        let meeting: MeetingContextProvider = StaticMeetingContext(placeName: "HackTX")
        return SelfEnrollModel(perception: ScriptedPerception(), frames: SilentFrameSource(), store: InMemoryPeopleStore(), contacts: NoopContactsBridge(), speaker: LogSpeaker(), cueGate: nil, meeting: meeting, userName: "Priya")
    }

    @MainActor
    static func make(services s: Services, runtime: FlowRuntime, state: AppState) -> SelfEnrollModel {
        let fixture = useFixture
        let frames: FrameSource
        if fixture {
            if let clip = VideoFileFrameSource(fixtureNamed: "enroll_marcus") { frames = clip } else { frames = SilentFrameSource() }
        } else {
            frames = PhoneCameraFrameSource(position: .front)
        }
        let perception: Perception
        var config = SelfEnrollModel.Config.default
        if s.scripted != nil {
            perception = ScriptedPerception()
            config.minEmbeddings = 3   // the scripted fake hands out three embeddings per track
        } else {
            let embedder = (s.perception as? PerceptionPipeline)?.embedder ?? PerceptionFactory.defaultEmbedder()
            let threshold = UserDefaults.standard.object(forKey: UserSettings.matchThreshold) as? Float ?? 0.40
            perception = PerceptionFactory.make(embedder: embedder, threshold: threshold)
        }
        let store: PeopleStore = runtime.peopleStore ?? s.peopleStore
        let contacts: ContactsBridge = runtime.contacts ?? s.contacts
        let meeting: MeetingContextProvider = runtime.meeting ?? StaticMeetingContext(placeName: state.placeName)
        // Only one AVCaptureSession at a time: pause the wearer's back camera while the stranger uses the front one.
        let pausesMain = !fixture && s.frameSource is PhoneCameraFrameSource
        return SelfEnrollModel(perception: perception, frames: frames, store: store, contacts: contacts, speaker: s.speaker, cueGate: s.cueGate, meeting: meeting, userName: state.userName, mirrorsPreview: !fixture, config: config,
                               onBegin: { if pausesMain { s.frameSource.stop() } },
                               onEnd: { if pausesMain { try? await s.frameSource.start() } })
    }
}

#Preview {
    SelfEnrollView(model: SelfEnrollFactory.preview(), onClose: {})
}
