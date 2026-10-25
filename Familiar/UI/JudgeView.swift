import SwiftUI
import QuartzCore

/// Pure, snapshot-friendly stage: the camera preview, boxes drawn in a Canvas, name pills, and a floating HUD with the
/// last cues, fps, audio route, consent state and the mic meter. `RoomView` feeds it live values. The HUD rides inside
/// the clipped stage only while there is room for it (see `showsInlineHUD`); otherwise the host lays it out below.
struct JudgeStageView: View {
    let tracks: [TrackSnapshot]
    let preview: CGImage?
    let fps: Double
    let route: String
    let micLevel: Float
    let consent: String
    let cues: [String]

    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// From the severe profile or accessibility Dynamic Type sizes the HUD would overrun the fixed-aspect stage and be
    /// cut off, so it moves under the stage. Hosts use the same test to know when to show it themselves.
    static func showsInlineHUD(scale: VisionScale, dynamicTypeSize: DynamicTypeSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize && !scale.prefersStackedLayout
    }

    private var hudIsInline: Bool { JudgeStageView.showsInlineHUD(scale: scale, dynamicTypeSize: dynamicTypeSize) }

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
                        let color = known ? FamiliarPalette.mint : FamiliarPalette.inkSecondary(scale)
                        let path = Path(roundedRect: rect, cornerRadius: 14)
                        if known { context.fill(path, with: .color(color.opacity(0.12))) }
                        let width: CGFloat = (known ? 3 : 2) + (scale.highContrast ? 1 : 0)
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: known ? [] : [8, 6]))
                    }
                }
                .accessibilityHidden(true)
                ForEach(tracks, id: \.trackID) { (track: TrackSnapshot) in
                    let rect = self.rect(for: track, in: geo.size)
                    label(for: track)
                        .offset(x: rect.minX, y: max(8, rect.minY - 30 * scale.textScale))
                }
                if hudIsInline {
                    VStack {
                        Spacer()
                        hud
                    }
                    .padding(12)
                }
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
            Text(known ? (track.identity.name ?? "") : "person").font(FamiliarType.micro(scale))
            if let score { Text(score).font(FamiliarType.mono(scale)) }
            Text(track.distance.words).font(FamiliarType.micro(scale))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(known ? FamiliarPalette.mint(scale) : FamiliarPalette.surface(scale), in: Capsule())
        .overlay(Capsule().strokeBorder(known ? Color.clear : FamiliarPalette.stroke(scale), lineWidth: scale.highContrast ? 2 : 1))
        .foregroundStyle(known ? knownLabelInk : FamiliarPalette.ink(scale))
        .fixedSize()
    }

    /// The letter colour `Monogram` uses on the same pigment: fixed navy on mint in both appearances (9.5:1; the
    /// dynamic ink would be near-white on mint in dark mode), white only on the deep teal of light high contrast.
    private var knownLabelInk: Color {
        scale.highContrast && colorScheme == .light ? Color.white : Color(familiarHex: "#172236")
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 10) {
            CueTicker(cues: cues)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    chips
                    Spacer(minLength: 0)
                    MicMeter(level: micLevel)
                }
                VStack(alignment: .leading, spacing: 8) {
                    chips
                    MicMeter(level: micLevel)
                }
            }
        }
        .padding(14)
        .background(FamiliarPalette.surface(scale).opacity(scale.highContrast ? 1 : 0.92),
                    in: RoundedRectangle(cornerRadius: FamiliarPalette.controlRadius, style: .continuous))
    }

    @ViewBuilder private var chips: some View {
        StatusChip(text: String(format: "%.0f fps", fps), systemImage: "speedometer")
        StatusChip(text: route, systemImage: "headphones")
        StatusChip(text: consent, systemImage: "hand.raised", tint: FamiliarPalette.ocean)
    }

    private var noSignal: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .visionIcon(scale, base: 40)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("Waiting for frames")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var description: String {
        let known = tracks.compactMap { $0.identity.name }
        let others = tracks.count - known.count
        let people = "\(known.isEmpty ? "No known people" : known.joined(separator: ", ")). \(others) other \(others == 1 ? "person" : "people")."
        let status = "Consent \(consent). \(String(format: "%.0f", fps)) frames per second."
        return "Camera view. \(people) \(status) Last cue: \(cues.last ?? "none yet")."
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
                PrivacyBanner(text: JudgeView.banner)
                diagnostics
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .navigationTitle("Room")   // hidden here; names the Back button on a pushed person
        .toolbar(.hidden, for: .navigationBar)
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
                       cues: recentCues)
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
    static let banner = "Known people only. Strangers are \"a person\". Faces never leave this phone."
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
                   cues: ["Normal mode.", "Three people.", "Marcus, ahead, close."])
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
        .padding(FamiliarPalette.margin)
        .familiarCanvas()
}
