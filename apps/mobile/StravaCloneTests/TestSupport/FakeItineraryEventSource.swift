import Foundation
@testable import StravaClone

/// Simulated realtime events (ADR-030 §9): `send` yields one, `finish` ends the stream.
final class FakeItineraryEventSource: ItineraryEventSource, @unchecked Sendable {
    private let stream: AsyncStream<ItineraryEvent>
    private let continuation: AsyncStream<ItineraryEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream<ItineraryEvent>.makeStream()
    }

    func events() async -> AsyncStream<ItineraryEvent> {
        stream
    }

    func send(_ event: ItineraryEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}
