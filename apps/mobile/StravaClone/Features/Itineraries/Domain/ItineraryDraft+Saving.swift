import Foundation

/// Why the draft cannot be saved yet.
enum ItinerarySaveIssue: Error, Equatable, Sendable {
    /// A start and a finish are needed.
    case incomplete
    /// A `follow` Leg is still being computed.
    case legsComputing
    /// A `follow` Leg waits for routing to be available again: only "Save" waits (ADR-030 §2).
    case legsPending
    /// The name must have 1 to 100 characters once trimmed.
    case invalidName
}

extension ItineraryDraft {
    static let nameLength = 1 ... 100

    /// Nothing but the name stands in the way of saving.
    var saveIssue: ItinerarySaveIssue? {
        guard waypoints.count >= 2 else { return .incomplete }
        if hasPendingLegs {
            return .legsPending
        }
        let isComputing = legs.contains { $0.mode == .follow && ($0.state != .computed || $0.path == nil) }
        return isComputing ? .legsComputing : nil
    }

    /// The `POST /v1/itineraries` request for this draft, under the app-generated `id`.
    func creation(id: ItineraryID, name: String) throws(ItinerarySaveIssue) -> ItineraryCreation {
        if let saveIssue {
            throw saveIssue
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.nameLength.contains(trimmed.count) else { throw .invalidName }
        // No save issue: every `follow` Leg is computed, so the geometry exists.
        guard let geometry else { throw .legsComputing }
        return ItineraryCreation(id: id, name: trimmed, sport: sport, geometry: geometry)
    }
}
