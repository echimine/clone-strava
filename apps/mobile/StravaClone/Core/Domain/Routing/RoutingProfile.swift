import Foundation

/// Mapbox Directions profile, derived from the sport category (no separate setting).
enum RoutingProfile: String, Hashable, Sendable {
    case walking, cycling
}

/// How the athlete moves; decides which paths the router may take. Shared by Itineraries
/// (ADR-030 §2) and the Return path of a Recording (ADR-031 §7).
enum SportCategory: Hashable, Sendable {
    case foot, wheels

    var routingProfile: RoutingProfile {
        switch self {
        case .foot: .walking
        case .wheels: .cycling
        }
    }
}
