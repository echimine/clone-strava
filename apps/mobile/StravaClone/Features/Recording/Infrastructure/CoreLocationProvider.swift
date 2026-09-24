import CoreLocation
import Foundation

/// Core Location adapter of `LocationProvider` (ADR-006), based on the iOS 17
/// `CLLocationUpdate.liveUpdates` async sequence. `CLBackgroundActivitySession`
/// keeps updates flowing with the screen locked (`location` background mode).
@MainActor
final class CoreLocationProvider: LocationProvider {
    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?

    func start() async -> AsyncStream<LocationSample> {
        await stop()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        backgroundSession = CLBackgroundActivitySession()

        let (stream, continuation) = AsyncStream<LocationSample>.makeStream()
        updates = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let location = update.location else { continue }
                    continuation.yield(LocationSample(location))
                }
            } catch {
                // TODO: expose authorization and Core Location errors to the Recording domain.
            }
            continuation.finish()
        }
        return stream
    }

    func stop() async {
        updates?.cancel()
        updates = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }
}

private extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}
