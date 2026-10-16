import Foundation

/// What happens to an open Activity's engagement elsewhere (ADR-034 §5): identifiers only, the
/// detail reloads what it shows through the API. `activity.updated` / `activity.deleted` are
/// `ActivityEvent`s, followed by the detail store itself (ADR-033 §8).
enum ActivityLiveEvent: Equatable, Sendable {
    case commentCreated(UUID)
    case commentUpdated(UUID)
    case commentDeleted(UUID)
    /// Count, `viewerHasKudoed` or givers changed.
    case kudosChanged
    /// The connection is back and the Activity subscribed again: what was missed meanwhile is
    /// reloaded (catch-up, ADR-010 §7).
    case reconnected
}

/// Live events port (ADR-007): the realtime `activity:{id}` topic in Infrastructure, faked in
/// tests.
/// Follows the `activity:{id}` topic of one open detail; `ActivityEventSource` follows `user:{id}`.
protocol ActivityLiveEventSource: Sendable {
    /// One Activity's events for as long as the stream is iterated: subscribed on start (and
    /// again after each reconnection), unsubscribed when the stream ends. It ends by itself once
    /// the Activity is deleted.
    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent>
}
