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
    private var updateBroadcaster: LocationBroadcaster<LocationUpdate>!
    private var headingBroadcaster: LocationBroadcaster<Double>!
    private var activeStreams = Set<String>()

    override init() {
        super.init()
        manager.delegate = self
        // One `liveUpdates` loop feeds both the map's samples and the Recording's updates.
        sampleBroadcaster = LocationBroadcaster { [weak self] active in
            self?.setStream("samples", active: active)
        }
        updateBroadcaster = LocationBroadcaster { [weak self] active in
            self?.setStream("updates", active: active)
        }
        headingBroadcaster = LocationBroadcaster { [weak self] active in
            active ? self?.manager.startUpdatingHeading() : self?.manager.stopUpdatingHeading()
        }
    }

    func samples() async -> AsyncStream<LocationSample> {
        sampleBroadcaster.subscribe()
    }

    func updates() async -> AsyncStream<LocationUpdate> {
        updateBroadcaster.subscribe(replaysLatest: false, bufferingPolicy: .unbounded)
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

    private func setStream(_ name: String, active: Bool) {
        let wasRunning = !activeStreams.isEmpty
        if active {
            activeStreams.insert(name)
        } else {
            activeStreams.remove(name)
        }
        switch (wasRunning, activeStreams.isEmpty) {
        case (false, false): startUpdates()
        case (true, true): stopUpdates()
        default: break
        }
    }

    private func startUpdates() {
        updates?.cancel()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    self?.publish(update)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.updateBroadcaster.send(LocationUpdate(issue: .failed(error.localizedDescription)))
            }
        }
    }

    private func publish(_ update: CLLocationUpdate) {
        let sample = update.location.map(LocationSample.init)
        if let sample {
            sampleBroadcaster.send(sample)
        }
        updateBroadcaster.send(LocationUpdate(sample: sample, isStationary: update.isStationary, issue: Self.issue(of: update)))
    }

    /// iOS 18 diagnostics; on iOS 17 an update simply has no position.
    private static func issue(of update: CLLocationUpdate) -> LocationIssue? {
        guard #available(iOS 18, *) else { return nil }
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
            return .denied
        }
        if update.accuracyLimited { return .accuracyLimited }
        if update.locationUnavailable { return .unavailable }
        return nil
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
            speed: location.speed >= 0 ? location.speed : nil,
            timestamp: location.timestamp
        )
    }
}
