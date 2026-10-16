import Foundation
@testable import StravaClone

/// Simulated `activity:{id}` subscription: `send` yields an event to the open detail;
/// `subscribedIds` is what is subscribed right now (until the detail stops iterating).
final class FakeActivityLiveEventSource: ActivityLiveEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: (ActivityID, AsyncStream<ActivityLiveEvent>.Continuation)] = [:]

    var subscribedIds: [ActivityID] { lock.withLock { continuations.values.map(\.0) } }

    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<ActivityLiveEvent>.makeStream()
        continuation.onTermination = { @Sendable [weak self] _ in self?.remove(key) }
        lock.withLock { continuations[key] = (activityId, continuation) }
        return stream
    }

    private func remove(_ key: UUID) {
        lock.withLock { continuations[key] = nil }
    }

    func send(_ event: ActivityLiveEvent) {
        for (_, continuation) in lock.withLock({ Array(continuations.values) }) {
            continuation.yield(event)
        }
    }
}
