import Foundation

/// `ItineraryEventSource` on top of the shared realtime connection (ADR-010): keeps only
/// `itinerary.saved` / `itinerary.deleted` (ADR-030 §9).
struct RealtimeItineraryEventSource: ItineraryEventSource {
    let client: WebSocketClient

    func events() async -> AsyncStream<ItineraryEvent> {
        let realtime = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in realtime {
                    if let event = Self.event(from: event) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// `{ itineraryId, updatedAt? }` (#28). `updatedAt` is read like the API's dates, so an
    /// echo compares equal to the row cached from the API's answer.
    private struct Payload: Decodable {
        let itineraryId: String
        let updatedAt: Date?
    }

    /// The Itinerary event a realtime message carries; nil for any other or unreadable one.
    static func event(from event: RealtimeEvent) -> ItineraryEvent? {
        guard let payload = try? APIClient.decoder.decode(Payload.self, from: event.data),
              let id = ItineraryID(payload.itineraryId) else {
            return nil
        }
        switch event.type {
        case "itinerary.saved": return payload.updatedAt.map { .saved(id: id, updatedAt: $0) }
        case "itinerary.deleted": return .deleted(id: id)
        default: return nil
        }
    }
}
