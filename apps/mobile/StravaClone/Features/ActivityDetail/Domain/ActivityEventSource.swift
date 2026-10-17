import Foundation

/// A realtime event about an Activity (ADR-033 §8).
enum ActivityEvent: Hashable, Sendable {
    /// `activity.updated`: new metadata, or new official values after a sport change (§5).
    case updated(ActivityID)
    /// `activity.deleted` (#94): the card goes, an open detail becomes unavailable.
    case deleted(ActivityID)
}

/// Realtime events about Activities (ADR-010), implemented over the shared connection in
/// Infrastructure, faked in tests.
/// Follows the `user:{id}` topic (the viewer's own Activities; an open detail's `activity:{id}`
/// subscription brings others' onto the same connection); `ActivityLiveEventSource` follows `activity:{id}`.
protocol ActivityEventSource: Sendable {
    func activityEvents() async -> AsyncStream<ActivityEvent>
}
