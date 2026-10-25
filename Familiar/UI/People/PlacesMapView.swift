import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// One place where someone said yes. Built from `Person.met`; only people with coordinates appear on the map.
struct MetPlace: Identifiable, Equatable {
    let id: UUID
    let personName: String
    /// The place the user confirmed, or the same fallback `Person.metPlaceText` uses (never an inferred address).
    let placeText: String
    let date: Date
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init?(person: Person) {
        guard let lat = person.met.latitude, let lon = person.met.longitude else { return nil }
        id = person.id
        personName = person.name
        placeText = person.metPlaceText
        date = person.met.at
        latitude = lat
        longitude = lon
    }

    var dateText: String { date.formatted(date: .abbreviated, time: .shortened) }
}

/// "Where you met": a MapKit map with one named marker per person who has a location, and the same places as a
/// VoiceOver-friendly list underneath. Locations are only ever the ones saved at the moment someone said yes,
/// on this phone; nothing is tracked. Pass `focus` to open centred on one person.
struct PlacesMapView: View {
    let people: [Person]
    let focus: Person?

    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition
    @State private var highlightedID: UUID?

    init(people: [Person], focus: Person? = nil) {
        self.people = people
        self.focus = focus
        let places: [MetPlace] = people.compactMap { MetPlace(person: $0) }
        var initial: MapCameraPosition = .automatic
        if let focus, let place = places.first(where: { $0.id == focus.id }) {
            initial = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 700, longitudinalMeters: 700))
        }
        _position = State(initialValue: initial)
        _highlightedID = State(initialValue: focus?.id)
    }

    private var places: [MetPlace] {
        people.compactMap { MetPlace(person: $0) }.sorted { $0.date > $1.date }
    }

    private var withoutLocation: [Person] {
        people.filter { $0.metCoordinate == nil }.sorted { $0.met.at > $1.met.at }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let focus {
                    Eyebrow(text: "Where you met \(focus.name)")
                        .padding(.horizontal, 4)
                }
                if places.isEmpty {
                    MetPlacesEmptyHero(hasPeople: !people.isEmpty)
                } else {
                    mapCard
                    header
                    VStack(spacing: 10) {
                        ForEach(places) { place in
                            MetPlaceRow(place: place, highlighted: place.id == highlightedID, onShow: { show(place) })
                        }
                    }
                }
                if !withoutLocation.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Without a map location")
                            .padding(.horizontal, 4)
                        ForEach(withoutLocation) { person in
                            MetNoLocationRow(person: person)
                        }
                    }
                }
                Text("Familiar keeps a location only when location access was allowed at the moment someone said yes. Everything here stays on this phone.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .padding(.horizontal, 4)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .navigationTitle("Where you met")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Map

    private var mapCard: some View {
        Map(position: $position) {
            ForEach(places) { place in
                Annotation(place.personName, coordinate: place.coordinate, anchor: .bottom) {
                    MetPlaceMarker(name: place.personName, highlighted: place.id == highlightedID)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.heroRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FamiliarPalette.heroRadius, style: .continuous).strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mapSummary)
        .accessibilityHint("The list below has the same places")
    }

    private var mapHeight: CGFloat { 320 * min(scale.textScale, 1.25) }

    private var mapSummary: String {
        let names = places.map { $0.personName }.joined(separator: ", ")
        let count = places.count == 1 ? "one place" : "\(places.count) places"
        return "Map of \(count) where you met \(names)."
    }

    /// The count and the one-line promise; only when there is a map above it (the empty hero carries its own words).
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(places.count == 1 ? "1 place" : "\(places.count) places")
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
            Text("Only places where someone said yes.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .padding(.horizontal, 4)
    }

    /// Flies the camera when motion is allowed; cuts straight to the place otherwise.
    private func show(_ place: MetPlace) {
        let animates = FamiliarMotion.animates(scale, reduceMotion: reduceMotion)
        withAnimation(animates ? Animation.easeInOut(duration: 0.6) : nil) {
            highlightedID = place.id
            position = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))
        }
        UIAccessibility.post(notification: .announcement, argument: "Map centred on \(place.placeText), where you met \(place.personName).")
    }
}

// MARK: - Pieces

/// A monogram pin on the map; larger with an ocean ring when it is the focused person. `Monogram` applies the
/// icon scale itself, so base sizes are passed here.
private struct MetPlaceMarker: View {
    let name: String
    let highlighted: Bool
    @Environment(\.visionScale) private var scale

    /// Ocean for the focused pin; white otherwise, except in high contrast where the ink ring must stay visible.
    private var ringColor: Color {
        if highlighted { return FamiliarPalette.ocean(scale) }
        return scale.highContrast ? FamiliarPalette.strokeStrong : FamiliarPalette.surface
    }

    var body: some View {
        VStack(spacing: 0) {
            Monogram(name: name, size: highlighted ? 44 : 34)
                .overlay(Circle().strokeBorder(ringColor, lineWidth: highlighted ? 3 : 2))
                .shadow(color: Color.black.opacity(scale.highContrast ? 0 : 0.18), radius: 6, y: 3)
            PinTail()
                .fill(ringColor)
                .frame(width: 12, height: 8)
                .offset(y: -1)
        }
        .accessibilityHidden(true)
    }
}

/// A small downward triangle for the pin tail.
private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One place in the list; tapping centres the map. A single VoiceOver element.
private struct MetPlaceRow: View {
    let place: MetPlace
    let highlighted: Bool
    let onShow: () -> Void
    @Environment(\.visionScale) private var scale

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 14) {
                Monogram(name: place.personName, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.personName)
                        .font(FamiliarType.title(scale))
                        .foregroundStyle(FamiliarPalette.ink(scale))
                    Text(place.placeText)
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    Text(place.dateText)
                        .font(FamiliarType.mono(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
                Spacer(minLength: 8)
                Image(systemName: highlighted ? "location.fill" : "location")
                    .visionIcon(scale, base: 18)
                    .foregroundStyle(highlighted ? FamiliarPalette.ocean(scale) : FamiliarPalette.inkSecondary(scale))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: 16)
            .overlay(RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous).strokeBorder(FamiliarPalette.ocean(scale), lineWidth: highlighted ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.personName). \(place.placeText). \(place.dateText).\(highlighted ? " Shown on the map." : "")")
        .accessibilityHint("Centres the map on this place")
    }
}

/// A person met without a saved location: still listed, never guessed.
private struct MetNoLocationRow: View {
    let person: Person
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(spacing: 14) {
            Monogram(name: person.name, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                Text(person.metLine)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                Text("No map location")
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name). \(person.metLine). No map location.")
    }
}

/// Shown in place of the map when no one has coordinates.
private struct MetPlacesEmptyHero: View {
    let hasPeople: Bool
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .visionIcon(scale, base: 34)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            Text(hasPeople ? "No map locations yet" : "No places yet")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(hasPeople
                 ? "Familiar saves a map location only when location access is allowed. The places and dates you have are listed below."
                 : "When someone says yes, where you met them appears here.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .surfaceCard(radius: FamiliarPalette.heroRadius, padding: 24)
    }
}

// MARK: - Previews

#Preview("Where you met") {
    NavigationStack { PlacesMapView(people: PeoplePreviewData.people, focus: PeoplePreviewData.marcus) }
}

#Preview("Where you met, no locations") {
    NavigationStack { PlacesMapView(people: [PeoplePreviewData.sam]) }
}

#Preview("Where you met, empty") {
    NavigationStack { PlacesMapView(people: []) }
}
