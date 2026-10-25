import SwiftUI
import QuartzCore

/// Pure, snapshot-friendly stage: the camera preview, boxes drawn in a Canvas, name pills, and a floating glass HUD
/// with the last cues, fps, audio route, consent state and the mic meter. `JudgeView` feeds it live values.
struct JudgeStageView: View {
    let tracks: [TrackSnapshot]
    let preview: CGImage?
    let fps: Double
    let route: String
    let micLevel: Float
    let consent: String
    let cues: [String]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    noSignal
                }
                Canvas { context, size in
                    for track in tracks {
                        let rect = self.rect(for: track, in: size)
                        let known = track.identity.isKnown
                        let color = known ? FamiliarTheme.known : FamiliarTheme.unknown
                        let path = Path(roundedRect: rect, cornerRadius: 12)
                        if known { context.fill(path, with: .color(color.opacity(0.10))) }
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: known ? 3 : 2, dash: known ? [] : [8, 6]))
                    }
                }
                .accessibilityHidden(true)
                ForEach(tracks, id: \.trackID) { track in
                    let rect = self.rect(for: track, in: geo.size)
                    label(for: track)
                        .offset(x: rect.minX, y: max(8, rect.minY - 30))
                }
                VStack {
                    Spacer()
                    hud
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private func rect(for track: TrackSnapshot, in size: CGSize) -> CGRect {
        CGRect(x: track.faceBox.minX * size.width,
               y: track.faceBox.minY * size.height,
               width: track.faceBox.width * size.width,
               height: track.faceBox.height * size.height)
    }

    private func label(for track: TrackSnapshot) -> some View {
        let known = track.identity.isKnown
        let color = known ? FamiliarTheme.known : FamiliarTheme.unknown
        let score = track.identity.score.map { String(format: "%.2f", $0) }
        return HStack(spacing: 6) {
            Text(known ? (track.identity.name ?? "") : "person").font(.familiarCaption.weight(.bold))
            if let score { Text(score).font(.familiarMono) }
            Text(track.distance.words).font(.familiarCaption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
        .foregroundStyle(.black)
        .fixedSize()
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 10) {
            CueTicker(cues: cues)
            HStack(spacing: 8) {
                StatusPill(text: String(format: "%.0f fps", fps), systemImage: "speedometer")
                StatusPill(text: route, systemImage: "headphones")
                StatusPill(text: consent, systemImage: "hand.raised", color: FamiliarTheme.consent)
                Spacer(minLength: 0)
                MicMeter(level: micLevel)
            }
        }
        .padding(16)
        .glassCard()
    }

    private var noSignal: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyeglasses").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Waiting for frames").font(.familiarBody).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var description: String {
        let known = tracks.compactMap { $0.identity.name }
        let others = tracks.count - known.count
        return "Camera view. \(known.isEmpty ? "No known people" : known.joined(separator: ", ")). \(others) other \(others == 1 ? "person" : "people"). Consent \(consent). \(String(format: "%.0f", fps)) frames per second."
    }
}

/// What the judges see on the table: the stage above, a short status strip and the recent transcript and events below.
struct JudgeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime

    static let banner = "Known people only. Strangers are \"a person\". Faces never leave this phone."

    var body: some View {
        VStack(spacing: 12) {
            PrivacyBanner(text: Self.banner)
            JudgeStageView(tracks: coordinator.tracks,
                           preview: coordinator.preview,
                           fps: coordinator.fps,
                           route: coordinator.services?.audioInput.route.title ?? "–",
                           micLevel: coordinator.services?.audioInput.micLevel ?? 0,
                           consent: ConsentStateLabel.text(runtime.consentState),
                           cues: coordinator.utterances.suffix(3).map { $0.utterance.text })
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: FamiliarTheme.cardRadius, style: .continuous))
            details
        }
        .padding(.horizontal, 12)
        .familiarScreen()
        .navigationTitle("Judge view")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(state.mode.title) · \(state.muted ? "muted" : "live") · \(state.source.title) · \(runtime.people.count) remembered · name guess \(runtime.nameGuess?.name ?? "–")")
                    .font(.familiarMono)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Status: \(state.mode.title) mode, \(state.muted ? "muted" : "live"), \(runtime.people.count) people remembered")
                let cutoff = CACurrentMediaTime() - 10
                ForEach(Array(coordinator.transcript.filter { $0.end >= cutoff }.suffix(3).enumerated()), id: \.offset) { _, segment in
                    Text("\(segment.speaker == .user ? "you" : segment.speaker == .other ? "other" : "?"): \(segment.text)")
                        .font(.familiarBody)
                }
                ForEach(coordinator.events.suffix(8).reversed()) { event in
                    Text(event.text).font(.familiarMono).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(radius: 18)
        }
    }
}
