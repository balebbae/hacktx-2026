import SwiftUI

/// Full-screen flow for a sighted stranger holding the phone: intro → front camera scan → name → consent → done.
/// Large type, every control labelled; the wearer only hears the heads-up and the result.
struct SelfEnrollView: View {
    @ObservedObject var model: SelfEnrollModel
    let onClose: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .background(Color(.systemBackground))
        .onAppear { model.open() }
        .animation(.default, value: model.step)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text(stepTitle).font(.headline).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            Spacer()
            switch model.step {
            case .done, .cancelled, .saving: EmptyView()
            default:
                Button("Cancel", role: .cancel) { Task { await model.cancel(); onClose() } }
                    .accessibilityHint("Stops and saves nothing")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .intro:
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 64)).accessibilityHidden(true)
            bigText(model.introText)
            Text("You will see yourself on the camera, type your name, then tap YES or No. Your face never leaves this phone.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .scanning:
            scanPreview
            bigText(model.hint)
                .accessibilityLabel("Scanning. \(model.hint)")
            if let err = model.error { Text(err).foregroundStyle(.red).font(.footnote).accessibilityLabel("Camera problem: \(err)") }
        case .name:
            Image(systemName: "textformat").font(.system(size: 48)).accessibilityHidden(true)
            bigText("What should \(model.userName) call you?")
            TextField("Your first name", text: $model.name)
                .font(.title2).textFieldStyle(.roundedBorder).textContentType(.givenName).submitLabel(.next)
                .focused($nameFocused)
                .onSubmit { model.submitName() }
                .accessibilityLabel("Your first name").accessibilityHint("Used when the wearer is told you are nearby")
            TextField("Phone (optional)", text: $model.phone)
                .font(.title3).textFieldStyle(.roundedBorder).keyboardType(.phonePad).textContentType(.telephoneNumber)
                .accessibilityHint("Saved to the contact so they can call or text you")
            Text("Only your name is said out loud. Nothing is saved yet.").font(.footnote).foregroundStyle(.secondary)
        case .consent, .saving:
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 56)).accessibilityHidden(true)
            bigText(model.consentText)
            if model.step == .saving { ProgressView("Saving…").accessibilityLabel("Saving") }
            if let err = model.error { Text(err).foregroundStyle(.red).font(.footnote) }
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green).accessibilityHidden(true)
            bigText(model.doneText)
            Text("\(model.userName) will hear your name when you walk up. You can be removed at any time from People.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .cancelled:
            Image(systemName: "xmark.circle").font(.system(size: 64)).accessibilityHidden(true)
            bigText("Nothing saved. Hand the phone back.")
        }
    }

    private var scanPreview: some View {
        ZStack {
            if let img = model.preview {
                Image(decorative: img, scale: 1)
                    .resizable().scaledToFill()
                    .scaleEffect(x: model.mirrorsPreview ? -1 : 1, y: 1)
            } else {
                Color(.secondarySystemFill)
                Image(systemName: "camera").font(.system(size: 48)).foregroundStyle(.secondary)
            }
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(8)
        }
        .frame(width: 280, height: 280)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera preview, \(model.collected) of \(model.config.targetEmbeddings) face samples")
    }

    @ViewBuilder private var footer: some View {
        switch model.step {
        case .intro:
            bigButton("Yes, scan my face", systemImage: "camera.viewfinder", tint: .accentColor) { Task { await model.beginScan() } }
                .accessibilityHint("Turns on the front camera for a few seconds")
            Button("No thanks") { Task { await model.cancel(); onClose() } }
                .font(.title3).accessibilityHint("Closes this screen and saves nothing")
        case .scanning:
            bigButton("Next", systemImage: "arrow.right", tint: .accentColor) { model.finishScan() }
                .disabled(!model.canContinueScan)
                .accessibilityHint(model.canContinueScan ? "Go on to your name" : "Enabled once enough face samples are collected")
        case .name:
            bigButton("Next", systemImage: "arrow.right", tint: .accentColor) { model.submitName() }
                .disabled(!model.canSubmitName)
                .accessibilityHint("Shows the permission question")
        case .consent, .saving:
            HStack(spacing: 16) {
                answerButton("No", yes: false, color: .red)
                answerButton("YES", yes: true, color: .green)
            }
            .disabled(model.step == .saving)
            Text("Faces stay on this phone. You can be removed any time.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .done, .cancelled:
            bigButton("Done", systemImage: "hand.raised", tint: .accentColor) { Task { await model.close(); onClose() } }
                .accessibilityHint("Closes this screen")
        }
    }

    private func bigText(_ s: String) -> some View {
        Text(s)
            .font(.system(.title, design: .rounded).weight(.semibold))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
    }

    private func bigButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private func answerButton(_ title: String, yes: Bool, color: Color) -> some View {
        Button { Task { await model.answer(yes: yes); if !yes { onClose() } } } label: {
            Text(title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .accessibilityLabel(yes ? "Yes, remember me" : "No, do not remember me")
        .accessibilityHint(yes ? "Saves your face on this phone only" : "Nothing is saved")
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
