import Foundation
@testable import StravaClone

/// Fake `LocationProvider` (ADR-025 §3, ADR-027): multi-subscriber like the real one,
/// driven by `send(_:)`, recording background-tracking calls and subscriber activity.
@MainActor
final class FakeLocationProvider: LocationProvider {
    private(set) var beginBackgroundTrackingCount = 0
    private(set) var endBackgroundTrackingCount = 0
    private(set) var isUpdating = false

    private lazy var sampleBroadcaster = LocationBroadcaster<LocationSample> { [weak self] active in
        self?.isUpdating = active
    }
    private lazy var headingBroadcaster = LocationBroadcaster<Double> { _ in }

    var sampleSubscriberCount: Int { sampleBroadcaster.subscriberCount }

    func samples() async -> AsyncStream<LocationSample> {
        sampleBroadcaster.subscribe()
    }

    func headings() async -> AsyncStream<Double> {
        headingBroadcaster.subscribe()
    }

    func beginBackgroundTracking() async {
        beginBackgroundTrackingCount += 1
    }

    func endBackgroundTracking() async {
        endBackgroundTrackingCount += 1
    }

    func send(_ sample: LocationSample) {
        sampleBroadcaster.send(sample)
    }
}

extension LocationSample {
    static func fixture(latitude: Double, longitude: Double, accuracy: Double = 5) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            altitude: nil,
            horizontalAccuracy: accuracy,
            timestamp: Date()
        )
    }
}
