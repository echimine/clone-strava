import Foundation

/// Fans one source of values out to any number of `AsyncStream` subscribers (ADR-027).
/// Replays the last value to a new subscriber and reports when the first subscriber
/// arrives / the last one leaves, so the source only runs while someone listens.
@MainActor
final class LocationBroadcaster<Value: Sendable> {
    private(set) var latest: Value?
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    private let onActiveChange: @MainActor (Bool) -> Void

    init(onActiveChange: @escaping @MainActor (Bool) -> Void) {
        self.onActiveChange = onActiveChange
    }

    var subscriberCount: Int { continuations.count }

    /// - Parameters:
    ///   - replaysLatest: hands the last value to the new subscriber at once (the map puck);
    ///     the Recording never wants a stale position (ADR-031 §3).
    ///   - bufferingPolicy: `.unbounded` for a subscriber that must not lose a sample.
    func subscribe(
        replaysLatest: Bool = true,
        bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy = .bufferingNewest(16)
    ) -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: bufferingPolicy)
        if replaysLatest, let latest {
            continuation.yield(latest)
        }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.remove(id) }
        }
        continuations[id] = continuation
        if continuations.count == 1 {
            onActiveChange(true)
        }
        return stream
    }

    func send(_ value: Value) {
        latest = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        guard continuations.removeValue(forKey: id) != nil else { return }
        if continuations.isEmpty {
            onActiveChange(false)
        }
    }
}
