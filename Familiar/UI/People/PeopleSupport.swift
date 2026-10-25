import SwiftUI
import CoreLocation

// Helpers shared by the People screens (list, detail, places map, invitation sheet).
// Nothing here talks to a service: pure formatting over `Person`, plus deterministic preview data.

extension Person {
    /// "Met at HackTX, UT Austin, Oct 24, 2026" or, without a place, "Met Oct 24, 2026".
    var metLine: String {
        if let place = met.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            return "Met at \(place), \(metDateText)"
        }
        return "Met \(metDateText)"
    }

    /// "Oct 24, 2026"
    var metDateText: String { met.at.formatted(date: .abbreviated, time: .omitted) }

    /// "October 24, 2026 at 10:00 AM"
    var metLongText: String { met.at.formatted(date: .long, time: .shortened) }

    /// The place the user confirmed, or a plain fallback (never an inferred address).
    var metPlaceText: String {
        if let place = met.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty { return place }
        return "Place not saved"
    }

    /// True when the person said yes inside the last `window` seconds (default one day).
    func isRecent(now: Date, window: TimeInterval = 86_400) -> Bool {
        now.timeIntervalSince(met.at) < window
    }

    /// Map coordinate of the meeting, when location was allowed at the time.
    var metCoordinate: CLLocationCoordinate2D? {
        guard let lat = met.latitude, let lon = met.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// How they agreed, in words.
    var consentKindText: String { consent.kind == .spoken ? "Said yes out loud" : "Tapped yes" }

    /// The system symbol for how they agreed.
    var consentKindSymbol: String { consent.kind == .spoken ? "waveform" : "hand.tap" }
}

/// The two filter chips above the people list.
enum PeopleFilter: String, CaseIterable, Hashable, Identifiable {
    case all, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .recent: return "Recent"
        }
    }
}

/// A navigation payload that is `Hashable` by id, so a `Person` can ride `navigationDestination(item:)`
/// without adding a retroactive `Hashable` conformance to the Core model.
struct PersonSelection: Hashable, Identifiable {
    let person: Person
    var id: UUID { person.id }
    static func == (lhs: PersonSelection, rhs: PersonSelection) -> Bool { lhs.person.id == rhs.person.id }
    func hash(into hasher: inout Hasher) { hasher.combine(person.id) }
}

/// Deterministic sample people for previews. Fixed dates and ids keep `ImageRenderer` snapshots stable.
enum PeoplePreviewData {
    /// 2026-10-24 10:00 CDT
    static let metDate = Date(timeIntervalSince1970: 1_792_854_000)
    /// 2026-10-23 15:30 CDT
    static let earlierDate = Date(timeIntervalSince1970: 1_792_787_400)
    /// 2026-10-20 09:00 CDT
    static let olderDate = Date(timeIntervalSince1970: 1_792_504_800)

    private static func embeddings(_ count: Int) -> [FaceEmbedding] {
        (0..<count).map { i in
            FaceEmbedding(modelID: "w600k_mbf", vector: Array(repeating: 0.1, count: 8), quality: 0.9 - Float(i) * 0.05, timestamp: Double(i), thumbnailJPEG: nil)
        }
    }

    static let marcus = Person(
        id: UUID(uuidString: "8C9B3C1E-6A7E-4F7B-9A7D-2A5E6E1B0001")!,
        name: "Marcus",
        phone: "512 555 0142",
        embeddings: embeddings(3),
        thumbnailPath: "",
        consent: ConsentRecord(kind: .spoken, at: metDate, askedText: "Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?", replyTranscript: "Yes, sure.", clipURL: nil),
        met: MeetingContext(at: metDate, placeName: "HackTX, UT Austin", latitude: 30.2862, longitude: -97.7394),
        contactIdentifier: "preview-marcus")

    static let maya = Person(
        id: UUID(uuidString: "8C9B3C1E-6A7E-4F7B-9A7D-2A5E6E1B0002")!,
        name: "Maya",
        phone: nil,
        embeddings: embeddings(2),
        thumbnailPath: "",
        consent: ConsentRecord(kind: .tap, at: earlierDate, askedText: "Priya would like to recognize you next time you meet. Okay to remember your face?", replyTranscript: "", clipURL: nil),
        met: MeetingContext(at: earlierDate, placeName: "Gregory Gym", latitude: 30.2840, longitude: -97.7366),
        contactIdentifier: nil)

    static let sam = Person(
        id: UUID(uuidString: "8C9B3C1E-6A7E-4F7B-9A7D-2A5E6E1B0003")!,
        name: "Sam",
        phone: "512 555 0199",
        embeddings: embeddings(4),
        thumbnailPath: "",
        consent: ConsentRecord(kind: .spoken, at: olderDate, askedText: "Priya would like to recognize you next time you meet. Okay to remember your face, Sam?", replyTranscript: "Yeah, of course.", clipURL: nil),
        met: MeetingContext(at: olderDate, placeName: "Career fair", latitude: nil, longitude: nil),
        contactIdentifier: nil)

    static let people: [Person] = [marcus, maya, sam]
}
