import SwiftUI
import QuartzCore

/// What the judges see on the table: preview with labelled boxes, match score, last utterances, transcript, event log,
/// mic meter, audio route, FPS, consent state and the privacy banner.
struct JudgeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime

    static let banner = "Known people only. Strangers are \"a person\". Faces never leave this phone."

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.banner)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.15))
                .accessibilityAddTraits(.isHeader)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.black
                    if let cg = coordinator.preview {
                        Image(decorative: cg, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                    }
                    ForEach(coordinator.tracks, id: \.trackID) { t in
                        trackBox(t, in: geo.size)
                    }
                    statusOverlay
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(previewDescription)
            footer
        }
        .navigationTitle("Judge view")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trackBox(_ t: TrackSnapshot, in size: CGSize) -> some View {
        let known = t.identity.isKnown
        let r = CGRect(x: t.faceBox.minX * size.width, y: t.faceBox.minY * size.height, width: t.faceBox.width * size.width, height: t.faceBox.height * size.height)
        let score = t.identity.score.map { String(format: " %.2f", $0) } ?? ""
        let label = known ? "\(t.identity.name ?? "")\(score) · \(t.distance.words)" : "person\(score) · \(t.distance.words)"
        return ZStack(alignment: .topLeading) {
            Rectangle().stroke(known ? Color.green : Color.gray, style: StrokeStyle(lineWidth: 2, dash: known ? [] : [6, 4])).frame(width: r.width, height: r.height)
            Text(label).font(.caption2.bold()).padding(2)
                .background(known ? Color.green : Color.gray).foregroundStyle(.black)
                .offset(y: -16)
        }
        .position(x: r.midX, y: r.midY)
    }

    private var statusOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            HStack(spacing: 8) {
                Text(String(format: "%.0f fps", coordinator.fps))
                Text(coordinator.services?.audioInput.route.title ?? "–")
                micMeter
                Spacer()
                Text("consent: \(consentLabel)")
            }
            .font(.caption2.monospaced()).padding(6).frame(maxWidth: .infinity).background(.black.opacity(0.55)).foregroundStyle(.white)
        }
    }

    private var micMeter: some View {
        let level = coordinator.services?.audioInput.micLevel ?? 0
        let n = Int((level * 6).rounded())
        return Text("mic " + String(repeating: "▮", count: n) + String(repeating: "▯", count: max(0, 6 - n)))
    }

    private var previewDescription: String {
        let known = coordinator.tracks.compactMap { $0.identity.name }
        let others = coordinator.tracks.count - known.count
        return "Camera preview. \(known.isEmpty ? "No known people" : known.joined(separator: ", ")). \(others) other \(others == 1 ? "person" : "people"). Consent \(consentLabel). \(String(format: "%.0f", coordinator.fps)) frames per second."
    }

    private var footer: some View {
        List {
            Section("Status") {
                Text("\(state.mode.title) · \(state.muted ? "muted" : "unmuted") · \(state.source.title) · \(runtime.people.count) remembered · name guess \(runtime.nameGuess?.name ?? "–")")
                    .font(.footnote.monospaced())
                    .accessibilityLabel("Status: \(state.mode.title) mode, \(state.muted ? "muted" : "unmuted"), \(runtime.people.count) people remembered")
            }
            Section("Last utterances") {
                ForEach(coordinator.utterances.suffix(3).reversed()) { e in
                    HStack {
                        Text(e.utterance.text).font(.body.weight(.medium))
                        Spacer()
                        if let w = e.window { Text(String(format: "%.0f ms", (w.lowerBound - e.at) * 1000)).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Transcript (last 10 s)") {
                let cutoff = CACurrentMediaTime() - 10
                ForEach(Array(coordinator.transcript.filter { $0.end >= cutoff }.suffix(4).enumerated()), id: \.offset) { _, seg in
                    Text("\(seg.speaker == .user ? "you" : seg.speaker == .other ? "other" : "?"): \(seg.text)").font(.footnote)
                }
            }
            Section("Events") {
                ForEach(coordinator.events.suffix(12).reversed()) { e in
                    Text(e.text).font(.caption.monospaced())
                }
            }
        }
        .listStyle(.plain)
    }

    private var consentLabel: String { ConsentStateLabel.text(runtime.consentState) }
}
