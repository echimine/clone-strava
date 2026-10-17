import Foundation
import os

/// A change to an Activity made away from the feed (ADR-033 §7), e.g. on its detail screen.
enum ActivityChange: Hashable, Sendable {
    /// New metadata or official values: the card is replaced by this one.
    case updated(ActivityPost)
    /// Deleted, or no longer visible: the card goes.
    case deleted(ActivityID)
    /// A deletion the server turned down (ADR-033 §7, optimistic): the card comes back where
    /// it was.
    case restored(ActivityID)
    /// New kudos or comment counts.
    case engagement(ActivityID, ActivityEngagement)
}

/// Core-level stream of `ActivityChange`s (ADR-033 §7): the detail publishes, the feed applies,
/// and neither feature imports the other (ADR-007 rule 5); the app shell hands both the same
/// instance. Any number of subscribers; a change is delivered to those subscribed when it is
/// published, in order, nothing is replayed.
final class ActivityChanges: Sendable {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<ActivityChange>.Continuation]())

    init() {}

    func publish(_ change: ActivityChange) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(change)
        }
    }

    /// Subscribed as soon as this returns, so nothing published afterwards is missed.
    func subscribe() -> AsyncStream<ActivityChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ActivityChange>.makeStream()
        continuation.onTermination = { @Sendable [continuations] _ in
            _ = continuations.withLock { $0.removeValue(forKey: id) }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }
}
