import Foundation
import CoreLocation
import os

/// Supplies the `MeetingContext` stored with each person.
protocol MeetingContextProvider: AnyObject {
    func current() -> MeetingContext
}

/// A fixed context (tests, Simulator without location).
final class StaticMeetingContext: MeetingContextProvider {
    var placeName: String?
    init(placeName: String? = nil) { self.placeName = placeName }
    func current() -> MeetingContext { MeetingContext(at: Date(), placeName: placeName, latitude: nil, longitude: nil) }
}

/// One when-in-use fix at launch and one reverse-geocode, cached for the session. The Settings place name wins.
final class LocationMeetingContext: NSObject, MeetingContextProvider, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let state = OSAllocatedUnfairLock(initialState: (location: CLLocation?.none, place: String?.none))
    /// Returns the user's override from Settings ("HackTX, UT Austin"); empty means "use the geocoder".
    private let placeOverride: () -> String?

    init(placeOverride: @escaping () -> String?) {
        self.placeOverride = placeOverride
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// One fix per launch. The readiness checklist owns the permission prompt; pass `askPermission` to prompt here instead.
    func start(askPermission: Bool = false) {
        switch manager.authorizationStatus {
        case .notDetermined: if askPermission { manager.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func current() -> MeetingContext {
        let snapshot = state.withLock { $0 }
        let override = placeOverride()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = (override?.isEmpty == false) ? override : snapshot.place
        return MeetingContext(at: Date(), placeName: place, latitude: snapshot.location?.coordinate.latitude, longitude: snapshot.location?.coordinate.longitude)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        state.withLock { $0.location = loc }
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            guard let self, let m = marks?.first else { return }
            let name = [m.name, m.locality].compactMap { $0 }.joined(separator: ", ")
            if !name.isEmpty { self.state.withLock { $0.place = name } }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
