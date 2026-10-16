import Foundation

/// What happens to an open Activity elsewhere (ADR-034 §5): identifiers only, the detail reloads
/// what it shows through the API.
enum ActivityLiveEvent: Equatable, Sendable {
    case commentCreated(UUID)
    case commentUpdated(UUID)
    case commentDeleted(UUID)
    /// Count, `viewerHasKudoed` or givers changed.
    case kudosChanged
    case activityUpdated
    case activityDeleted
    /// The connection is back and the Activity subscribed again: what was missed meanwhile is
    /// reloaded (catch-up, ADR-010 §7).
    case reconnected
}

/// Live events port (ADR-007): the realtime `activity:{id}` topic in Infrastructure, faked in
/// tests.
protocol ActivityLiveEventSource: Sendable {
    /// One Activity's events for as long as the stream is iterated: subscribed on start (and
    /// again after each reconnection), unsubscribed when the stream ends.
    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent>
}
