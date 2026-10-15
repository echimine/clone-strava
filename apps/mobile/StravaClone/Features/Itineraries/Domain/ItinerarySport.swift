import Foundation

/// Sports an Itinerary can be planned for (ADR-030 §2): the sports with GPS, never swimming.
enum ItinerarySport: String, CaseIterable, Hashable, Sendable {
    case run, ride, walk, hike

    var sportType: SportType {
        SportType(code: rawValue)
    }

    /// Category of the sport in the reference data (`sports.sport_type.category`).
    var category: SportCategory {
        switch self {
        case .run, .walk, .hike: .foot
        case .ride: .wheels
        }
    }

    var routingProfile: RoutingProfile {
        category.routingProfile
    }
}
