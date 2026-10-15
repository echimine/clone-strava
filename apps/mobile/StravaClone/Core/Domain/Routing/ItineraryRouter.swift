import Foundation

/// Computes the path of one or more consecutive Legs (ADR-030 §2): Mapbox Directions in
/// the app, a fake network in tests.
protocol ItineraryRouter: Sendable {
    /// Path through `waypoints` (2 to 25, in order), one geometry per Leg.
    /// Throws a `RoutingError`, or `CancellationError` when the task is cancelled.
    func path(through waypoints: [Coordinate], profile: RoutingProfile) async throws -> RoutedPath
}

/// Router answer for consecutive Legs.
struct RoutedPath: Equatable, Sendable {
    /// Waypoints snapped to the network, same count and order as requested.
    let waypoints: [Coordinate]
    /// One geometry per Leg (`waypoints.count - 1`), from its first to its last Waypoint.
    let legs: [[Coordinate]]
}

/// Routing failures, classified by what the editor does about them.
enum RoutingError: Error, Equatable, Sendable {
    /// No path within reach (nothing near a Waypoint, or no connection): the Leg goes straight.
    case noPath
    /// Network failure, timeout, server error: worth retrying later.
    case temporary
    /// `429`, the token's quota is used up: retry with backoff.
    case rateLimited
}
