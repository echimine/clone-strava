import CoreLocation
import Observation
import UIKit

enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

/// App-wide location permission (ADR-027 §5), injected through the SwiftUI environment.
/// The only place that requests authorization. Its manager never starts updates: GPS
/// fixes come from `CoreLocationProvider` alone.
@Observable
@MainActor
final class LocationPermissionService: NSObject {
    private(set) var authorization: LocationAuthorization = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorization = Self.map(manager.authorizationStatus)
    }

    var isAuthorized: Bool { authorization == .authorized }

    func requestWhenInUseIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .denied
        }
    }
}

extension LocationPermissionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = Self.map(status)
        }
    }
}
