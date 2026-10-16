import Foundation
@testable import StravaClone

/// `ActivityEventSource` driven by the test: every subscriber gets what `send` sends.
final class FakeActivityEventSource: ActivityEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ActivityEvent>.Continuation] = [:]

    var subscriberCount: Int { lock.withLock { continuations.count } }

    func activityEvents() async -> AsyncStream<ActivityEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ActivityEvent>.makeStream()
        continuation.onTermination = { @Sendable [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        lock.withLock { continuations[id] = continuation }
        return stream
    }

    func send(_ event: ActivityEvent) {
        for continuation in lock.withLock({ Array(continuations.values) }) {
            continuation.yield(event)
        }
    }
}
