import Foundation
import CoreLocation
import Contacts

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Callback for location updates
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
    }

    // Convert coordinates to human-readable address
    func getAddress(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            return formatAddress(from: placemark)
        } catch {
            print("Geocoding error: \(error)")
            return nil
        }
    }

    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []

        // Street address
        if let street = placemark.thoroughfare,
           let number = placemark.subThoroughfare {
            components.append("\(number) \(street)")
        } else if let street = placemark.thoroughfare {
            components.append(street)
        }

        // City
        if let city = placemark.locality {
            components.append(city)
        }

        // State
        if let state = placemark.administrativeArea {
            components.append(state)
        }

        // Country
        if let country = placemark.country {
            components.append(country)
        }

        return components.joined(separator: ", ")
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                self.currentLocation = location
                self.onLocationUpdate?(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            // We no longer auto-start tracking here to conserve battery and stealth.
            // Tracking is now managed explicitly by RecordingManager via startTracking/stopTracking.
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        switch clError?.code {
        case .denied:
            print("📍 Location permission denied - recordings will not have GPS data")
        case .locationUnknown:
            print("📍 Location temporarily unavailable - will retry")
        default:
            print("📍 Location error: \(error.localizedDescription)")
        }
    }
}
