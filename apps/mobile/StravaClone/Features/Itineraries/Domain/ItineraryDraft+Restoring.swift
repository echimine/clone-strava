import Foundation

extension ItineraryDraft {
    /// A saved Itinerary reopened as stored (ADR-030 §5): every Leg keeps its mode, and a
    /// `follow` Leg its path, so nothing needs routing. `nil` when the Legs do not join the
    /// Waypoints (Legs = Waypoints − 1).
    init?(restoring saved: SavedItinerary) {
        guard saved.waypoints.count >= 2, saved.legs.count == saved.waypoints.count - 1 else { return nil }
        self.init(
            sport: saved.sport,
            waypoints: saved.waypoints.map { Waypoint(id: WaypointID(), coordinate: $0) },
            legs: saved.legs.map { leg in
                switch leg {
                case .follow(let path):
                    Leg(id: LegID(), mode: .follow, path: path.decode(), version: 0, state: .computed)
                case .straight:
                    Leg(id: LegID(), mode: .straight, path: nil, version: 0, state: .computed)
                }
            }
        )
    }
}
