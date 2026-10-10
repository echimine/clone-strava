import Foundation

/// A change made from the detail screen, applied locally at once and sent later through the
/// `sync_operation` queue (ADR-008 §3, ADR-030 §8).
enum ItineraryChange: Equatable, Sendable {
    /// `PATCH /v1/itineraries/:id`.
    case rename(name: String)
    /// `DELETE /v1/itineraries/:id`.
    case delete
}

/// A change waiting to be sent.
struct PendingItineraryChange: Equatable, Sendable {
    /// The queue's own id: a newer change for the same Itinerary gets a new one.
    let id: Int64
    let itineraryID: ItineraryID
    let change: ItineraryChange
    /// Failed sends so far.
    let attempts: Int
    /// Not sent before this date, unless a trigger says the network is back.
    let nextAttemptAt: Date
}

/// A change the server turned down: it is dropped and a toast says so.
enum ItineraryChangeRefusal: Equatable, Sendable {
    case rename
    case delete
}

/// Storage of the pending changes (ADR-008 §3), coalesced per Itinerary: only the last rename
/// is kept and a delete cancels a pending rename. While a change is pending, the cache shows
/// the local value (renamed, or hidden) whatever the server says. Implemented over GRDB.
protocol ItineraryChangeQueue: Sendable {
    /// Records a change, due at `date`. A rename of an Itinerary pending deletion is ignored.
    func enqueue(_ change: ItineraryChange, for id: ItineraryID, at date: Date) async throws
    /// Every pending change, oldest first.
    func pending() async throws -> [PendingItineraryChange]
    /// One more failed send: not tried again before `date`.
    func postpone(_ change: PendingItineraryChange, until date: Date, error: String) async throws
    /// Sent or dropped. A newer change for the same Itinerary stays.
    func remove(_ change: PendingItineraryChange) async throws
    /// Sign-out: forgets every pending change.
    func clear() async throws
}

enum ItineraryName {
    /// The name as saved (trimmed), or nil when it does not have 1 to 100 characters.
    static func validated(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ItineraryDraft.nameLength.contains(trimmed.count) ? trimmed : nil
    }
}
