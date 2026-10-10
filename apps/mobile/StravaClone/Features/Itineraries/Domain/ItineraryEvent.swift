import Foundation

/// A change to one of the athlete's Itineraries, relayed live on `user:{id}` (ADR-030 §9).
/// It may come from this very device: a save is then the echo of its own write.
enum ItineraryEvent: Equatable, Sendable {
    /// Created, edited or renamed; `updatedAt` is the one committed by the API.
    case saved(id: ItineraryID, updatedAt: Date)
    case deleted(id: ItineraryID)
}

/// Realtime port (ADR-007): implemented over the shared WebSocket, faked in tests. Events
/// missed while disconnected are not replayed: the resyncs cover them (ADR-030 §9).
protocol ItineraryEventSource: Sendable {
    func events() async -> AsyncStream<ItineraryEvent>
}
