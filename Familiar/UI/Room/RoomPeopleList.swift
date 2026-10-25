import SwiftUI

/// Two quiet counters: how many people you know are in view, and how many others stay unnamed. Digits pop in.
/// Side by side on the balanced design; stacked from the severe profile or accessibility Dynamic Type sizes.
struct RoomCountsRow: View {
    let known: Int
    let others: Int

    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { scale.prefersStackedLayout || dynamicTypeSize.isAccessibilitySize }

    private var layout: AnyLayout {
        stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        layout {
            tile(value: known, title: known == 1 ? "person you know" : "people you know", symbol: "person.fill.checkmark")
            tile(value: others, title: others == 1 ? "other, unnamed" : "others, unnamed", symbol: "person.fill.questionmark")
        }
    }

    private func tile(value: Int, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NumberPop(value: value, font: FamiliarType.titleXL(scale), color: FamiliarPalette.ink(scale))
                Image(systemName: symbol)
                    .visionIcon(scale, base: 16)
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            Text(title)
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(title)")
    }
}

/// The compact list under the radar: one `NearbyPersonCard` per known person, left to right, then one line for
/// everyone who stays unnamed. Also the whole Room when Dynamic Type is too large for a map.
struct RoomPeopleList: View {
    let tracks: [TrackSnapshot]
    var awarenessActive: Bool = true
    /// Everyone remembered on this phone, so a card can offer Details for the matching person (spec 20.5 §05).
    var people: [Person] = []
    /// Pushes the person's detail screen (Call, Text, Where we met, Remove). No action is shown without it.
    var onDetails: ((Person) -> Void)? = nil

    @Environment(\.visionScale) private var scale

    private var known: [TrackSnapshot] {
        tracks.filter { $0.identity.isKnown }.sorted { $0.bearing.degrees < $1.bearing.degrees }
    }
    private var others: Int { tracks.count - known.count }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(known, id: \.trackID) { (track: TrackSnapshot) in
                card(for: track)
            }
            if known.isEmpty {
                emptyLine
            }
            if others > 0 {
                othersLine
            }
        }
        .cardResize()
    }

    private func person(for track: TrackSnapshot) -> Person? {
        guard let id = track.identity.personID else { return nil }
        return people.first { $0.id == id }
    }

    /// One known person; Details appears only when the person is on this phone and the host can show them.
    private func card(for track: TrackSnapshot) -> some View {
        let name: String = track.identity.name ?? ""
        var action: (() -> Void)? = nil
        if let onDetails, let person = person(for: track) {
            action = { onDetails(person) }
        }
        return NearbyPersonCard(name: name,
                                direction: track.bearing.band.words,
                                distance: track.distance.words,
                                score: track.identity.score,
                                actionTitle: action == nil ? nil : "Details",
                                action: action,
                                actionHint: "Shows \(name)'s details: call, text, where you met, and removal")
    }

    private var emptyLine: some View {
        HStack(spacing: 12) {
            Image(systemName: awarenessActive ? "person.2" : "pause.circle")
                .visionIcon(scale, base: 20)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            Text(awarenessActive ? "No one you know is in view right now." : "Room awareness paused.")
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }

    private var othersLine: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill.questionmark")
                .visionIcon(scale, base: 18)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            Text(others == 1 ? "One other person remains unnamed." : "\(others) others remain unnamed.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Room list") {
    ScrollView {
        VStack(spacing: 16) {
            RoomCountsRow(known: 2, others: 2)
            RoomPeopleList(tracks: RoomRadarView.sampleTracks)
            RoomPeopleList(tracks: [], awarenessActive: false)
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}

#Preview("Room list, severe") {
    ScrollView {
        VStack(spacing: 16) {
            RoomCountsRow(known: 2, others: 2)
            RoomPeopleList(tracks: RoomRadarView.sampleTracks)
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
    .environment(\.visionScale, VisionScale.make(.severe))
}
