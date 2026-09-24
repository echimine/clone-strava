import Foundation

/// A recording in progress (local state `recording`, ADR-008 §2).
struct ActiveRecording: Equatable, Sendable {
    let id: ActivityID
    let startedAt: Date
    private(set) var distance: Distance = .zero
    private(set) var lastSample: LocationSample?

    init(id: ActivityID = ActivityID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }

    /// Adds a fix to the provisional distance (ADR-008 §6). Inaccurate fixes are ignored.
    mutating func append(_ sample: LocationSample, maxAccuracy: Double = 50) {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxAccuracy else { return }
        if let lastSample {
            distance = distance + lastSample.coordinate.distance(to: sample.coordinate)
        }
        lastSample = sample
    }
}
