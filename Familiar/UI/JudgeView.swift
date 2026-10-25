import SwiftUI
import QuartzCore

/// Pure, snapshot-friendly stage: the camera preview, boxes drawn in a Canvas, name pills, and a floating HUD with the
/// last cues, fps, audio route, consent state and the mic meter. `RoomView` feeds it live values.
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
                FamiliarPalette.canvasSecondary
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
                        let color = known ? FamiliarPalette.mint : FamiliarPalette.inkSecondary
                        let path = Path(roundedRect: rect, cornerRadius: 14)
                        if known { context.fill(path, with: .color(color.opacity(0.12))) }
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
        let score = track.identity.score.map { String(format: "%.2f", $0) }
        return HStack(spacing: 6) {
            Text(known ? (track.identity.name ?? "") : "person").font(FamiliarType.micro.weight(.semibold))
            if let score { Text(score).font(FamiliarType.mono) }
            Text(track.distance.words).font(FamiliarType.micro)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(known ? FamiliarPalette.mint : FamiliarPalette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(known ? Color.clear : FamiliarPalette.stroke, lineWidth: 1))
        .foregroundStyle(FamiliarPalette.ink)
        .fixedSize()
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 10) {
            CueTicker(cues: cues)
            HStack(spacing: 8) {
                StatusChip(text: String(format: "%.0f fps", fps), systemImage: "speedometer")
                StatusChip(text: route, systemImage: "headphones")
                StatusChip(text: consent, systemImage: "hand.raised", tint: FamiliarPalette.ocean)
                Spacer(minLength: 0)
                MicMeter(level: micLevel)
            }
        }
        .padding(14)
        .background(FamiliarPalette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: FamiliarPalette.controlRadius, style: .continuous))
    }

    private var noSignal: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyeglasses").font(.system(size: 40)).foregroundStyle(FamiliarPalette.inkSecondary)
            Text("Waiting for frames").font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var description: String {
        let known = tracks.compactMap { $0.identity.name }
        let others = tracks.count - known.count
        return "Camera view. \(known.isEmpty ? "No known people" : known.joined(separator: ", ")). \(others) other \(others == 1 ? "person" : "people"). Consent \(consent). \(String(format: "%.0f", fps)) frames per second."
    }
}

/// Room: live awareness of consenting known people only. Cards first, camera stage second, diagnostics folded away.
struct RoomView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("In the room").font(FamiliarType.titleXL).foregroundStyle(FamiliarPalette.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    StatusChip(text: "\(state.mode.title) cues", systemImage: "waveform")
                }
                Text(summary).font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)

                ForEach(knownTracks, id: \.trackID) { track in
                    NearbyPersonCard(name: track.identity.name ?? "", direction: track.bearing.band.words, distance: track.distance.words, score: track.identity.score)
                }
                if knownTracks.isEmpty {
                    Text(coordinator.fps > 0 ? "No one you know is in view right now." : "Room awareness paused.")
                        .font(FamiliarType.body)
                        .foregroundStyle(FamiliarPalette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCard()
                }

                JudgeStageView(tracks: coordinator.tracks,
                               preview: coordinator.preview,
                               fps: coordinator.fps,
                               route: coordinator.services?.audioInput.route.title ?? "–",
                               micLevel: coordinator.services?.audioInput.micLevel ?? 0,
                               consent: ConsentStateLabel.text(runtime.consentState),
                               cues: coordinator.utterances.suffix(3).map { $0.utterance.text })
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous).strokeBorder(FamiliarPalette.stroke, lineWidth: 1))

                PrivacyBanner(text: JudgeView.banner)

                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(state.source.title) · \(runtime.people.count) remembered · name guess \(runtime.nameGuess?.name ?? "–")")
                            .font(FamiliarType.mono).foregroundStyle(FamiliarPalette.inkSecondary)
                        let cutoff = CACurrentMediaTime() - 10
                        ForEach(Array(coordinator.transcript.filter { $0.end >= cutoff }.suffix(3).enumerated()), id: \.offset) { _, segment in
                            Text("\(segment.speaker == .user ? "you" : segment.speaker == .other ? "other" : "?"): \(segment.text)").font(FamiliarType.supporting)
                        }
                        ForEach(coordinator.events.suffix(8).reversed()) { event in
                            Text(event.text).font(FamiliarType.mono).foregroundStyle(FamiliarPalette.inkSecondary)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(FamiliarType.body.weight(.medium))
                .foregroundStyle(FamiliarPalette.ink)
                .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var knownTracks: [TrackSnapshot] {
        coordinator.tracks.filter { $0.identity.isKnown }.sorted { $0.bearing.degrees < $1.bearing.degrees }
    }

    private var summary: String {
        let others = coordinator.tracks.count - knownTracks.count
        let known = knownTracks.count
        let knownText = known == 0 ? "No known people in view." : "\(known) known \(known == 1 ? "person" : "people") in view."
        let othersText = others == 0 ? "" : " \(others) \(others == 1 ? "other remains" : "others remain") unnamed."
        return knownText + othersText
    }
}

/// Kept for the privacy banner text and older call sites; the Room tab is the judge-facing screen now.
struct JudgeView: View {
    static let banner = "Known people only. Strangers are \"a person\". Faces never leave this phone."
    var body: some View { RoomView() }
}
