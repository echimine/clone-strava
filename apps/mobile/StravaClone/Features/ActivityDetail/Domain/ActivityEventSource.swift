import Foundation

/// A realtime event about an Activity (ADR-033 §8).
enum ActivityEvent: Hashable, Sendable {
    /// `activity.updated`: new metadata, or new official values after a sport change (§5).
    case updated(ActivityID)
}

/// Realtime events about Activities (ADR-010), implemented over the shared connection in
/// Infrastructure, faked in tests.
protocol ActivityEventSource: Sendable {
    func activityEvents() async -> AsyncStream<ActivityEvent>
}
