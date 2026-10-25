import SwiftUI
import QuartzCore

/// What the judges see on the table: the preview with labelled boxes, the last utterances, the event log and the banner.
struct JudgeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator

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
        let label = known ? "\(t.identity.name ?? "") \(String(format: "%.2f", t.identity.score ?? 0))" : "person"
        return ZStack(alignment: .topLeading) {
            Rectangle().stroke(known ? Color.green : Color.gray, lineWidth: 2).frame(width: r.width, height: r.height)
            Text(label).font(.caption2.bold()).padding(2)
                .background(known ? Color.green : Color.gray).foregroundStyle(.black)
                .offset(y: -16)
        }
        .position(x: r.midX, y: r.midY)
    }

    private var previewDescription: String {
        let known = coordinator.tracks.compactMap { $0.identity.name }
        let others = coordinator.tracks.count - known.count
        return "Camera preview. \(known.isEmpty ? "No known people" : known.joined(separator: ", ")). \(others) other \(others == 1 ? "person" : "people")."
    }

    private var footer: some View {
        List {
            Section("Status") {
                Text("\(state.mode.title) · \(coordinator.services?.audioInput.route.title ?? "–") · \(String(format: "%.0f fps", coordinator.fps)) · consent \(consentLabel)")
                    .font(.footnote.monospaced())
            }
            Section("Last utterances") {
                ForEach(coordinator.utterances.suffix(3).reversed()) { e in
                    Text(e.utterance.text).font(.body.weight(.medium))
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

    private var consentLabel: String {
        switch coordinator.consentState {
        case .idle: return "idle"
        case .confirmingWithUser: return "confirming"
        case .gathering: return "gathering"
        case .asking: return "asking"
        case .listening: return "listening"
        case .saving: return "saving"
        case .done: return "done"
        case .declined: return "declined"
        case .cancelled: return "cancelled"
        }
    }
}
