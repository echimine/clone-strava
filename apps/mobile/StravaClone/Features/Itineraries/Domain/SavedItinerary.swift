import Foundation

/// A saved Itinerary as "Modifier" reopens it (ADR-030 §5, §8): its Waypoints and Legs as
/// stored, loaded online with `GET /v1/itineraries/:id`, so the editor shows them without
/// routing again. Never cached: the editor only works online.
struct SavedItinerary: Equatable, Sendable {
    let id: ItineraryID
    let name: String
    let sport: ItinerarySport
    /// Positions as stored (snapped for a snapped Waypoint); a `follow` Leg carries its
    /// stored path.
    let geometry: ItineraryGeometry
}
