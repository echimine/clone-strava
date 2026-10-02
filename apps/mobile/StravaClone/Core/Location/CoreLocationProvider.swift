import CoreLocation
import Foundation

/// Core Location adapter of `LocationProvider` (ADR-006, ADR-027): the only GPS
/// updates loop in the app, shared by the map puck and Recording.
/// Fixes come from the iOS 17 `CLLocationUpdate.liveUpdates` async sequence; headings
/// from the manager's delegate. Each runs only while it has subscribers.
/// `CLBackgroundActivitySession` keeps fixes flowing with the screen locked
/// (`location` background mode). Authorization is requested by `LocationPermissionService`.
@MainActor
final class CoreLocationProvider: NSObject, LocationProvider {
    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?
    private var sampleBroadcaster: LocationBroadcaster<LocationSample>!
    private var headingBroadcaster: LocationBroadcaster<Double>!

    override init() {
        super.init()
        manager.delegate = self
        sampleBroadcaster = LocationBroadcaster { [weak self] active in
            active ? self?.startUpdates() : self?.stopUpdates()
        }
        headingBroadcaster = LocationBroadcaster { [weak self] active in
            active ? self?.manager.startUpdatingHeading() : self?.manager.stopUpdatingHeading()
        }
    }

    func samples() async -> AsyncStream<LocationSample> {
        sampleBroadcaster.subscribe()
    }

    func headings() async -> AsyncStream<Double> {
        headingBroadcaster.subscribe()
    }

    func beginBackgroundTracking() async {
        backgroundSession?.invalidate()
        backgroundSession = CLBackgroundActivitySession()
    }

    func endBackgroundTracking() async {
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    private func startUpdates() {
        updates?.cancel()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let location = update.location else { continue }
                    self?.sampleBroadcaster.send(LocationSample(location))
                }
            } catch {
                // TODO: expose Core Location errors to subscribers.
            }
        }
    }

    private func stopUpdates() {
        updates?.cancel()
        updates = nil
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let direction = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        // The manager was created on the main thread, so its delegate is called there.
        MainActor.assumeIsolated {
            headingBroadcaster.send(direction)
        }
    }
}

private extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            course: location.course >= 0 ? location.course : nil,
            timestamp: location.timestamp
        )
    }
}
