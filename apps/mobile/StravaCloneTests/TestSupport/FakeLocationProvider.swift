import Foundation
@testable import StravaClone

/// Fake `LocationProvider` (ADR-025 §3, ADR-027): multi-subscriber like the real one,
/// driven by `send(_:)`, recording background-tracking calls and subscriber activity.
@MainActor
final class FakeLocationProvider: LocationProvider {
    private(set) var beginBackgroundTrackingCount = 0
    private(set) var endBackgroundTrackingCount = 0
    private var isSampleStreamActive = false
    /// Whether a Recording listens to `updates()`.
    private(set) var isRecordingStreamActive = false
    /// The GPS runs while anyone listens, the map or a Recording.
    var isUpdating: Bool { isSampleStreamActive || isRecordingStreamActive }

    private lazy var sampleBroadcaster = LocationBroadcaster<LocationSample> { [weak self] active in
        self?.isSampleStreamActive = active
    }
    private lazy var updateBroadcaster = LocationBroadcaster<LocationUpdate> { [weak self] active in
        self?.isRecordingStreamActive = active
    }
    private lazy var headingBroadcaster = LocationBroadcaster<Double> { _ in }

    var sampleSubscriberCount: Int { sampleBroadcaster.subscriberCount }
    var updateSubscriberCount: Int { updateBroadcaster.subscriberCount }

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
        beginBackgroundTrackingCount += 1
    }

    func endBackgroundTracking() async {
        endBackgroundTrackingCount += 1
    }

    /// A fix, to the map and to the Recording.
    func send(_ sample: LocationSample) {
        sampleBroadcaster.send(sample)
        updateBroadcaster.send(LocationUpdate(sample: sample))
    }

    /// An update without a position, or with a status.
    func send(_ update: LocationUpdate) {
        if let sample = update.sample {
            sampleBroadcaster.send(sample)
        }
        updateBroadcaster.send(update)
    }
}

extension LocationSample {
    static func fixture(latitude: Double, longitude: Double, accuracy: Double = 5, at timestamp: Date = Date()) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            altitude: nil,
            horizontalAccuracy: accuracy,
            timestamp: timestamp
        )
    }
}
