import SwiftUI
import QuartzCore

/// How sure Familiar is about a box, in the three colors the judge legend uses. Only consenting, enrolled people can be
/// `sure` or `unsure`; everyone else is a `stranger` and is never named.
enum JudgeConfidence: CaseIterable {
    case sure, unsure, stranger

    /// A match this far above the recognition threshold reads as sure; anything between the threshold and that is unsure.
    static let sureMargin: Float = 0.15

    static func of(_ track: TrackSnapshot, threshold: Float) -> JudgeConfidence {
        guard track.identity.isKnown, let score = track.identity.score else { return .stranger }
        return score >= threshold + sureMargin ? .sure : .unsure
    }

    var color: Color {
        switch self {
        case .sure: return Color(familiarHex: "#2FD27A")
        case .unsure: return Color(familiarHex: "#FFB020")
        case .stranger: return Color(familiarHex: "#C9CED8")
        }
    }

    var word: String {
        switch self {
        case .sure: return "Sure"
        case .unsure: return "Unsure"
        case .stranger: return "Stranger"
        }
    }

    var legend: String {
        switch self {
        case .sure: return "Sure match"
        case .unsure: return "Unsure"
        case .stranger: return "Stranger"
        }
    }
}

/// What kind of line the wearer just heard, for the caption's color bar and tag.
enum JudgeCaptionKind {
    case hazard, person, poyo, other

    init(_ u: Utterance) {
        switch u.category {
        case "hazard", "cloudscene": self = .hazard
        case "agent", "brain", "gist", "scene", "surroundings", "place", "action", "whereis": self = .poyo
        case "rollcall": self = .person
        default: self = u.personID != nil ? .person : .other
        }
    }

    var tag: String {
        switch self {
        case .hazard: return "Hazard"
        case .person: return "Person"
        case .poyo: return "Scene"
        case .other: return "Status"
        }
    }

    var color: Color {
        switch self {
        case .hazard: return Color(familiarHex: "#FF5A66")
        case .person: return JudgeConfidence.sure.color
        case .poyo: return Color(familiarHex: "#6EB4FF")
        case .other: return Color(familiarHex: "#E6E9F0")
        }
    }
}

/// Pure, snapshot-friendly stage for judges: the camera preview, confidence-colored boxes with name pills, a color
/// legend, and subtitles of exactly what the wearer was just told (plus what the mic heard). `RoomView` and
/// `JudgeModeView` feed it live values. Status chips ride inside the stage only while there is room for them (see
/// `showsInlineHUD`); otherwise the host lays them out below.
struct JudgeStageView: View {
    let tracks: [TrackSnapshot]
    let preview: CGImage?
    let fps: Double
    let route: String
    let micLevel: Float
    let consent: String
    let captions: [SpokenCue]
    var heard: [TranscriptSegment] = []
    var reading: SceneReading? = nil
    var threshold: Float = 0.40

    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A caption stays bright this long after it was spoken, then dims but stays readable until the next one.
    static let captionFresh: TimeInterval = 8
    private static let heardFresh: TimeInterval = 6
    private static let readingFresh: TimeInterval = 10
    private static let overlayInk = Color.white
    private static let overlayFill = Color.black.opacity(0.72)

    /// From the severe profile or accessibility Dynamic Type sizes the chips would overrun the fixed-aspect stage, so
    /// they move under the stage. Hosts use the same test to know when to show them themselves.
    static func showsInlineHUD(scale: VisionScale, dynamicTypeSize: DynamicTypeSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize && !scale.prefersStackedLayout
    }

    private var hudIsInline: Bool { JudgeStageView.showsInlineHUD(scale: scale, dynamicTypeSize: dynamicTypeSize) }

    private var spoken: [SpokenCue] {
        captions.filter { $0.utterance.audience == .user && !$0.utterance.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

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
                    for track in tracks { draw(track, in: size, context: &context) }
                }
                .accessibilityHidden(true)
                // Known names sit above their box and draw on top; strangers' pills hang below, so a crowd of
                // unnamed people never hides the one name the wearer was told.
                ForEach(tracks, id: \.trackID) { track in
                    let rect = self.rect(for: track, in: geo.size)
                    let named = JudgeConfidence.of(track, threshold: threshold) != .stranger
                    label(for: track)
                        .offset(x: min(max(4, rect.minX), max(4, geo.size.width - 150)),
                                y: named ? max(46 * scale.textScale, rect.minY - 30 * scale.textScale) : rect.maxY + 4)
                        .zIndex(named ? 1 : 0)
                }
                VStack(spacing: 8) {
                    topBar
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let now = CACurrentMediaTime()
                        VStack(alignment: .leading, spacing: 8) {
                            pathMarker(now: now, width: geo.size.width - 24)
                            heardLine(now: now)
                            caption(now: now)
                        }
                    }
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Boxes

    private func draw(_ track: TrackSnapshot, in size: CGSize, context: inout GraphicsContext) {
        let rect = self.rect(for: track, in: size)
        let band = JudgeConfidence.of(track, threshold: threshold)
        let color = band.color
        let path = Path(roundedRect: rect, cornerRadius: 10)
        let boost: CGFloat = scale.highContrast ? 1 : 0
        if band != .stranger { context.fill(path, with: .color(color.opacity(0.14))) }
        context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 5 + boost)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5 + boost, dash: band == .stranger ? [8, 6] : []))
        // Heavy corner brackets so the box still reads on a busy frame or a projector.
        let arm = min(22, rect.width / 3, rect.height / 3)
        var corners = Path()
        for (p, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            corners.move(to: CGPoint(x: p.x + dx * arm, y: p.y))
            corners.addLine(to: p)
            corners.addLine(to: CGPoint(x: p.x, y: p.y + dy * arm))
        }
        context.stroke(corners, with: .color(color), style: StrokeStyle(lineWidth: 5 + boost, lineCap: .round, lineJoin: .round))
    }

    private func rect(for track: TrackSnapshot, in size: CGSize) -> CGRect {
        // The preview is drawn aspect-fill, so map through the same scale and crop or the boxes drift off the faces.
        var shown = CGRect(origin: .zero, size: size)
        if let preview, preview.width > 0, preview.height > 0 {
            let iw = CGFloat(preview.width), ih = CGFloat(preview.height)
            let fill = max(size.width / iw, size.height / ih)
            shown = CGRect(x: (size.width - iw * fill) / 2, y: (size.height - ih * fill) / 2, width: iw * fill, height: ih * fill)
        }
        let b = track.faceBox
        let face = CGRect(x: shown.minX + b.minX * shown.width, y: shown.minY + b.minY * shown.height,
                          width: b.width * shown.width, height: b.height * shown.height)
        // A little margin, and never smaller than a fingertip, so far-away faces still get a visible box.
        let side = max(30, max(face.width, face.height) * 1.2)
        let grow = CGSize(width: max(0, side - face.width) / 2, height: max(0, side * 1.15 - face.height) / 2)
        return face.insetBy(dx: -grow.width, dy: -grow.height)
    }

    private func label(for track: TrackSnapshot) -> some View {
        let band = JudgeConfidence.of(track, threshold: threshold)
        let name = band == .stranger ? "Person" : (track.identity.name ?? "Person")
        return HStack(spacing: 6) {
            Text(name).font(FamiliarType.micro(scale).weight(.bold))
            if band != .stranger, let score = track.identity.score {
                Text("\(band.word) \(String(format: "%.2f", score))").font(FamiliarType.mono(scale))
            }
            Text(track.distance.words).font(FamiliarType.micro(scale))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(band.color, in: Capsule())
        .foregroundStyle(Color(familiarHex: "#0B1220"))
        .fixedSize()
    }

    // MARK: Overlays

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { legend; Spacer(minLength: 0); liveBadge }
            VStack(alignment: .leading, spacing: 6) { legend; liveBadge }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(JudgeConfidence.allCases, id: \.self) { band in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(band.color, lineWidth: 3).frame(width: 14, height: 14)
                    Text(band.legend).font(FamiliarType.micro(scale)).lineLimit(1)
                }
            }
        }
        .foregroundStyle(Self.overlayInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Self.overlayFill, in: Capsule())
    }

    @ViewBuilder private var liveBadge: some View {
        if hudIsInline {
            HStack(spacing: 6) {
                Circle().fill(preview == nil ? Color.gray : JudgeCaptionKind.hazard.color).frame(width: 8, height: 8)
                Text(preview == nil ? "No video" : String(format: "LIVE %.0f fps", fps)).font(FamiliarType.mono(scale))
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 12)
                Text("consent \(consent)").font(FamiliarType.mono(scale)).lineLimit(1)
            }
            .foregroundStyle(Self.overlayInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Self.overlayFill, in: Capsule())
        }
    }

    /// Subtitle of the last line the wearer actually heard, color-coded by kind.
    @ViewBuilder private func caption(now: TimeInterval) -> some View {
        let last = spoken.last
        let fresh = last.map { now - $0.at < Self.captionFresh } ?? false
        let kind = last.map { JudgeCaptionKind($0.utterance) } ?? .other
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(last == nil ? Color.gray : kind.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(last == nil ? "Wearer hears" : "Wearer hears · \(kind.tag)")
                    if let last { Text(Self.ago(now - last.at)).foregroundStyle(.white.opacity(0.6)) }
                }
                .font(FamiliarType.micro(scale).weight(.semibold))
                .foregroundStyle(last == nil ? Color.gray : kind.color)
                Text(last.map { "\u{201C}\($0.utterance.text)\u{201D}" } ?? "Nothing yet. Familiar stays quiet until something matters.")
                    .font(FamiliarType.companion(scale).weight(.semibold))
                    .foregroundStyle(Self.overlayInk.opacity(last == nil ? 0.7 : 1))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                    .id(last?.id)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(Color.black.opacity(fresh ? 0.8 : 0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(fresh ? kind.color.opacity(0.9) : .clear, lineWidth: 2))
        .opacity(fresh || last == nil ? 1 : 0.75)
        .animation(.easeOut(duration: 0.25), value: last?.id)
    }

    /// The mic's last few seconds, so a judge can see Familiar waits for gaps and hears the other person's "yes".
    @ViewBuilder private func heardLine(now: TimeInterval) -> some View {
        if let seg = heard.last(where: { now - $0.end < Self.heardFresh && !$0.text.isEmpty }) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text(seg.speaker == .user ? "Wearer said" : "Mic heard")
                    .fontWeight(.semibold)
                Text(seg.text).lineLimit(1).truncationMode(.head)
                MicMeter(level: micLevel).frame(maxWidth: 60)
            }
            .font(FamiliarType.micro(scale))
            .foregroundStyle(Self.overlayInk.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Self.overlayFill, in: Capsule())
        }
    }

    /// Where the walking path sits in the frame and whether it is clear, from the latest scene reading.
    @ViewBuilder private func pathMarker(now: TimeInterval, width: CGFloat) -> some View {
        if let r = reading, now - r.at < Self.readingFresh {
            let color: Color = r.path == .clear ? JudgeConfidence.sure.color : r.path == .caution ? JudgeConfidence.unsure.color : JudgeCaptionKind.hazard.color
            let text = [r.path == .clear ? "Path clear" : "Path \(r.path.rawValue)", r.pathWhat, r.pathMeters.map { String(format: "%.1f m", $0) }]
                .compactMap { $0 }.joined(separator: " · ")
            Label(text, systemImage: r.path == .clear ? "figure.walk" : "exclamationmark.triangle.fill")
                .font(FamiliarType.micro(scale).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color, in: Capsule())
                .foregroundStyle(Color(familiarHex: "#0B1220"))
                .fixedSize()
                .offset(x: max(0, min(width - 180, CGFloat(r.pathX) * width - 90)))
        }
    }

    static func ago(_ seconds: TimeInterval) -> String {
        seconds < 2 ? "now" : seconds < 60 ? "\(Int(seconds))s ago" : "\(Int(seconds / 60))m ago"
    }

    private var noSignal: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .visionIcon(scale, base: 40)
            Text("Waiting for frames")
                .font(FamiliarType.supporting(scale))
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var description: String {
        let boxes = tracks.map { t -> String in
            let band = JudgeConfidence.of(t, threshold: threshold)
            return band == .stranger ? "a person, \(t.distance.words)" : "\(t.identity.name ?? "a person"), \(band.word.lowercased()), \(t.distance.words)"
        }
        let people = boxes.isEmpty ? "No one in view." : "In view: \(boxes.joined(separator: "; "))."
        let status = "Consent \(consent). \(String(format: "%.0f", fps)) frames per second."
        return "Camera view. \(people) \(status) Wearer last heard: \(spoken.last?.utterance.text ?? "nothing yet")."
    }
}

/// Full-screen judge presentation: the stage as big as the phone allows, then the running log of everything said to
/// the wearer, color-coded, so someone at the table can follow along without hearing the glasses.
struct JudgeModeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionScale) private var scale
    let route: String
    let consent: String
    let micLevel: Float
    let threshold: Float

    private var tracks: [TrackSnapshot] { coordinator.isReady ? coordinator.tracks : [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What Familiar sees and says").font(FamiliarType.title(scale))
                    Text("Boxes show confidence. Captions are exactly what the wearer hears.")
                        .font(FamiliarType.supporting(scale)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Close judge view")
            }
            JudgeStageView(tracks: tracks, preview: coordinator.preview, fps: coordinator.fps, route: route,
                           micLevel: micLevel, consent: consent, captions: state.spokenCues,
                           heard: coordinator.transcript, reading: coordinator.sceneReading, threshold: threshold)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Said to the wearer").font(FamiliarType.micro(scale).weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = CACurrentMediaTime()
                VStack(alignment: .leading, spacing: 8) {
                    let log = Array(state.spokenCues.filter { $0.utterance.audience == .user && !$0.utterance.text.isEmpty }
                        .suffix(4).reversed())
                    if log.isEmpty {
                        Text("Nothing yet.").font(FamiliarType.supporting(scale)).foregroundStyle(.white.opacity(0.6))
                    }
                    ForEach(Array(log.enumerated()), id: \.offset) { (i: Int, cue: SpokenCue) in
                        let kind = JudgeCaptionKind(cue.utterance)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(kind.tag.uppercased()).font(FamiliarType.mono(scale)).foregroundStyle(kind.color)
                                .frame(width: 64, alignment: .leading)
                            Text(cue.utterance.text).font(i == 0 ? FamiliarType.body(scale) : FamiliarType.supporting(scale))
                                .foregroundStyle(.white.opacity(i == 0 ? 1 : 0.7))
                            Spacer(minLength: 0)
                            Text(JudgeStageView.ago(now - cue.at)).font(FamiliarType.mono(scale)).foregroundStyle(.white.opacity(0.5))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(JudgeView.banner).font(FamiliarType.micro(scale)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Color(familiarHex: "#05070C").ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Room: live awareness of consenting known people only. The radar and the cards first, the camera stage second,
/// diagnostics folded away. At accessibility text sizes the map steps aside and the list carries the room. Everything
/// drawn here comes from frames that are actually arriving; when they are not, the room says so and shows no one.
struct RoomView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(YouSettings.mimoPresence) private var mimoPresence = MimoPresence.full.rawValue
    @State private var showDiagnostics = false
    @State private var showJudgeMode = false
    /// A Details tap on a card pushes that person (same `PersonSelection` payload as the People tab).
    @State private var selection: PersonSelection?
    /// The start-up skeleton (`skeletonReveal`) shows only between the pipeline starting and its first frame, and
    /// never for longer than `startupGrace`: after that the honest "Room awareness paused." line comes back.
    @State private var sawFirstFrame = false
    @State private var startupWindowOver = false
    private static let startupGrace: Double = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryBlock
                VStack(alignment: .leading, spacing: 16) {
                    RoomCountsRow(known: knownTracks.count, others: othersCount)
                    if showsRadar {
                        RoomRadarView(tracks: liveTracks)
                            .surfaceCard(padding: 16)
                    }
                    RoomPeopleList(tracks: liveTracks,
                                   awarenessActive: awarenessLive,
                                   people: runtime.people,
                                   onDetails: { (person: Person) in selection = PersonSelection(person: person) })
                }
                .skeletonReveal(isLoaded: !startingUp)
                sayItButton
                stage
                judgeModeButton
                PrivacyBanner(text: JudgeView.banner)
                diagnostics
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .navigationTitle("Room")   // hidden here; names the Back button on a pushed person
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showJudgeMode) {
            JudgeModeView(route: routeTitle, consent: consentText, micLevel: micLevel, threshold: matchThreshold)
                .environmentObject(state)
                .environmentObject(coordinator)
        }
        .navigationDestination(item: $selection) { (sel: PersonSelection) in
            PersonDetailView(person: sel.person)
        }
        .onAppear { if awarenessLive { sawFirstFrame = true } }
        .onChange(of: awarenessLive) { _, live in
            if live { sawFirstFrame = true }
        }
        .task(id: coordinator.services == nil) { await endStartupWindow() }
    }

    // MARK: Pieces

    /// Mimo, the title, the cue chip and the pause chip in one row; the chips drop under the title when the row is
    /// too narrow, and stack when even two chips cannot share a line.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                headerTitle
                Spacer(minLength: 8)
                cueChip
                pauseChip
            }
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                HStack(spacing: 8) {
                    cueChip
                    pauseChip
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                cueChip
                pauseChip
            }
        }
    }

    private var headerTitle: some View {
        HStack(alignment: .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize && MimoPresence.stored(mimoPresence) != .hidden {
                MimoView(state: mimoState, size: 46, showsGlow: false)
            }
            Text("In the room")
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var cueChip: some View {
        StatusChip(text: "\(state.mode.title) cues", systemImage: "waveform")
            .accessibilityLabel("Cue level: \(state.mode.title)")
    }

    /// Spec 20.4: a clearly labeled pause control on every awareness screen, not only Today. Same path as Today's
    /// Pause pill (the cue gate plus "Muted." / "Unmuted.").
    private var pauseChip: some View {
        Button { togglePause() } label: {
            StatusChip(text: state.muted ? "Resume cues" : "Pause cues",
                       systemImage: state.muted ? "play" : "pause",
                       tint: FamiliarPalette.ink(scale))
                .visionHitTarget(scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.muted ? "Resume cues" : "Pause cues")
        .accessibilityHint(state.muted ? "Turns cues back on" : "Stops all cues except urgent ones")
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .contentTransition(.opacity)
            TimelineView(.periodic(from: .now, by: scale.simplifyMotion ? 5 : 1)) { _ in
                Text(freshness)
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(scale.spokenFirst ? 10 : 0)
    }

    private var judgeModeButton: some View {
        Button { showJudgeMode = true } label: {
            Label("Open judge view", systemImage: "rectangle.expand.vertical")
        }
        .buttonStyle(GhostPillStyle())
        .accessibilityHint("Shows the camera full screen with confidence boxes and captions of what the wearer hears")
    }

    private var matchThreshold: Float { UserDefaults.standard.object(forKey: UserSettings.matchThreshold) as? Float ?? 0.40 }

    private var sayItButton: some View {
        Button { whoIsHere() } label: {
            Label("Say who's here", systemImage: "speaker.wave.2")
        }
        .buttonStyle(GhostPillStyle())
        .accessibilityHint("Speaks the known people around you, then counts the others")
    }

    @ViewBuilder private var stage: some View {
        JudgeStageView(tracks: liveTracks,
                       preview: coordinator.preview,
                       fps: coordinator.fps,
                       route: routeTitle,
                       micLevel: micLevel,
                       consent: consentText,
                       captions: state.spokenCues,
                       heard: coordinator.transcript,
                       reading: coordinator.sceneReading,
                       threshold: matchThreshold)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous)
                .strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.highContrast ? 2 : 1))
        if !JudgeStageView.showsInlineHUD(scale: scale, dynamicTypeSize: dynamicTypeSize) {
            stageDetails
        }
    }

    /// The stage's HUD, laid out under the stage with room to wrap when the profile or Dynamic Type is large.
    private var stageDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            CueTicker(cues: recentCues)
            StatusChip(text: String(format: "%.0f fps", coordinator.fps), systemImage: "speedometer")
            StatusChip(text: routeTitle, systemImage: "headphones")
            StatusChip(text: consentText, systemImage: "hand.raised", tint: FamiliarPalette.ocean)
            MicMeter(level: micLevel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
    }

    private var diagnostics: some View {
        DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(state.source.title) · \(runtime.people.count) remembered · name guess \(runtime.nameGuess?.name ?? "–")")
                    .font(FamiliarType.mono(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                if let brain = runtime.brain {
                    PoyoPanel(brain: brain, reading: coordinator.sceneReading, scene: coordinator.services?.cloudScene)
                }
                if let agent = runtime.agent {
                    AgentPanel(session: agent)
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recentTranscript.enumerated()), id: \.offset) { (pair: (offset: Int, element: TranscriptSegment)) in
                            Text("\(speakerTag(pair.element.speaker)): \(pair.element.text)")
                                .font(FamiliarType.supporting(scale))
                                .foregroundStyle(FamiliarPalette.ink(scale))
                        }
                    }
                }
                ForEach(coordinator.events.suffix(8).reversed()) { (event: AppCoordinator.LoggedEvent) in
                    Text(event.text)
                        .font(FamiliarType.mono(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
            }
            .padding(.top, 8)
        }
        .font(FamiliarType.body(scale))
        .foregroundStyle(FamiliarPalette.ink(scale))
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityHint("Frame rate, transcript and event log for the table")
    }

    // MARK: Derived

    /// Frames are arriving from a started pipeline. Until then the room is honest: paused text, empty map, no counts.
    private var awarenessLive: Bool { coordinator.services != nil && coordinator.fps > 0 }

    /// The tracks the room may draw: the live ones, or none when nothing is being observed.
    private var liveTracks: [TrackSnapshot] { awarenessLive ? coordinator.tracks : [] }

    private var knownTracks: [TrackSnapshot] {
        liveTracks.filter { $0.identity.isKnown }.sorted { $0.bearing.degrees < $1.bearing.degrees }
    }

    private var othersCount: Int { liveTracks.count - knownTracks.count }

    /// The map needs room; at accessibility text sizes the list alone tells the room.
    private var showsRadar: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var mimoState: MimoState {
        if state.muted { return .paused }
        if !awarenessLive { return .disconnected }
        return knownTracks.isEmpty ? .idle : .cue
    }

    private var routeTitle: String { coordinator.services?.audioInput.route.title ?? "–" }
    private var micLevel: Float { coordinator.services?.audioInput.micLevel ?? 0 }
    private var consentText: String { Self.consentLabel(runtime.consentState) }
    /// From `AppState.spokenCues`, which both speakers feed, so the ticker works on a device as well as in the Simulator.
    private var recentCues: [String] { state.spokenCues.suffix(3).map { $0.utterance.text } }

    /// The pipeline has started but no frame has arrived yet, inside the grace window: the counts and the list show
    /// a skeleton rather than claiming "paused" for a camera that is still opening.
    private var startingUp: Bool {
        coordinator.services != nil && !awarenessLive && !sawFirstFrame && !startupWindowOver
    }

    private var summary: String {
        let others = othersCount
        let known = knownTracks.count
        let knownText = known == 0 ? "No known people in view." : "\(known) known \(known == 1 ? "person" : "people") in view."
        let othersText = others == 0 ? "" : " \(others) \(others == 1 ? "other remains" : "others remain") unnamed."
        return knownText + othersText
    }

    /// Reflects real observed timestamps (spec 05). Re-read every second by the `TimelineView` in `summaryBlock`.
    private var freshness: String {
        guard awarenessLive else { return startingUp ? "Waiting for the first frames." : "Room awareness paused." }
        guard let latest = coordinator.tracks.map({ $0.timestamp }).max() else { return "Watching for people." }
        let age = CACurrentMediaTime() - latest
        if age < 2 { return "Updated just now." }
        if age >= 60 { return "Updated over a minute ago." }
        let seconds = Int(age)
        return seconds == 1 ? "Updated a second ago." : "Updated \(seconds) seconds ago."
    }

    private var recentTranscript: [TranscriptSegment] {
        let cutoff = CACurrentMediaTime() - 10
        return Array(coordinator.transcript.filter { $0.end >= cutoff }.suffix(3))
    }

    private func speakerTag(_ guess: SpeakerGuess) -> String {
        switch guess {
        case .user: return "you"
        case .other: return "other"
        case .none: return "?"
        }
    }

    /// Short consent words for the stage chip. Lives here so the Room never depends on the demo controls' labels.
    private static func consentLabel(_ s: ConsentState) -> String {
        switch s {
        case .idle: return "idle"
        case .confirmingWithUser: return "confirming"
        case let .gathering(track): return "looking (track \(track))"
        case let .asking(name): return "asking \(name ?? "someone")"
        case .listening: return "listening"
        case .saving: return "saving"
        case let .done(person): return "done: \(person.name)"
        case .declined: return "declined"
        case let .cancelled(reason): return "cancelled: \(reason)"
        }
    }

    private func whoIsHere() {
        FamiliarHaptics.play(.listen)
        if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() }
    }

    /// Same as Today's Pause pill: the cue gate plus "Muted." / "Unmuted." through the coordinator.
    private func togglePause() {
        state.muted.toggle()
        coordinator.setMuted(state.muted)
        FamiliarHaptics.play(state.muted ? .paused : .accepted)
    }

    /// Runs when the pipeline appears (the task id flips): after the grace window the skeleton yields to the honest
    /// paused line whether or not a frame ever came. Before the pipeline exists there is nothing to wait for.
    private func endStartupWindow() async {
        guard coordinator.services != nil else { return }
        try? await Task.sleep(for: .seconds(Self.startupGrace))
        guard !Task.isCancelled else { return }
        startupWindowOver = true
    }
}

/// Kept for the privacy banner text and older call sites; the Room tab is the judge-facing screen now.
struct JudgeView: View {
    static let banner = "Known people only. Strangers are \"a person\". Faces are blacked out before any image leaves this phone."
    var body: some View { RoomView() }
}

#Preview("Room") {
    NavigationStack { RoomView() }
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "RoomViewPreview") ?? .standard))
        .environmentObject(AppCoordinator())
        .environmentObject(FlowRuntime())
}

#Preview("Room, severe") {
    NavigationStack { RoomView() }
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "RoomViewPreviewSevere") ?? .standard))
        .environmentObject(AppCoordinator())
        .environmentObject(FlowRuntime())
        .environment(\.visionScale, VisionScale.make(.severe))
}

#Preview("Camera stage") {
    JudgeStageView(tracks: RoomRadarView.sampleTracks, preview: nil, fps: 24,
                   route: "phone mic + glasses", micLevel: 0.6, consent: "idle",
                   captions: ["Normal mode.", "Three people.", "Marcus, ahead, close."].enumerated().map {
                       SpokenCue(utterance: Utterance(text: $0.element, priority: 2, category: "preview", personID: nil,
                                                      dedupeKey: nil, audience: .user, earcon: false),
                                 at: CACurrentMediaTime() - Double(2 - $0.offset))
                   })
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
        .padding(FamiliarPalette.margin)
        .familiarCanvas()
}

// MARK: - Poyo (vision brain + always-on scene)

struct PoyoPanel: View {
    @ObservedObject var brain: PoyoBrain
    let reading: SceneReading?
    let scene: CloudScene?
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let upload = scene?.lastUpload {
                    Image(decorative: upload, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(width: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Last image sent to the vision model, faces blacked out")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.map { "\($0.path.rawValue) · \($0.summary)" } ?? "no scene reading yet")
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.ink(scale))
                    let st = scene?.status
                    Text("uploads \(st?.uploads ?? 0) · scene \(st?.lastLatency.map { String(format: "%.1f s", $0) } ?? "–") · answer \(brain.lastLatency.map { String(format: "%.1f s", $0) } ?? "–")\(brain.busy ? " · thinking" : "")")
                        .font(FamiliarType.mono(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    if let e = st?.lastError {
                        Text(e).font(FamiliarType.micro(scale)).foregroundStyle(FamiliarPalette.danger)
                    }
                }
            }
            Button("Ask Poyo: what's in front of me?") { Task { await brain.ask("what's in front of me?") } }
                .font(FamiliarType.supporting(scale))
                .frame(minHeight: scale.hitTarget)
                .accessibilityHint("Sends a scripted question to Poyo")
            ForEach(brain.lines.suffix(6)) { line in
                Text("\(line.role.rawValue): \(line.text)")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
            }
        }
    }
}

// MARK: - S8 agent status (own view so `@ObservedObject` refreshes it without Combine plumbing)

struct AgentPanel: View {
    @ObservedObject var session: AgentSession
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("agent: \(session.status.label)")
                    .font(FamiliarType.mono(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .accessibilityLabel("Agent \(session.status.label)")
                Spacer()
                Button("Ask: what's around me?") { Task { await session.ask("what's around me") } }
                    .font(FamiliarType.supporting(scale))
                    .frame(minHeight: scale.hitTarget)
                    .accessibilityHint("Sends a scripted question to the assistant")
            }
            ForEach(session.transcript.suffix(6)) { line in
                Text("\(line.role.rawValue): \(line.text)")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
            }
            if !session.isConfigured {
                Text("no ELEVENLABS_AGENT_ID in Secrets.xcconfig")
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
        }
    }
}
