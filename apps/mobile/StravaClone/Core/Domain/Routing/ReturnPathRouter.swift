import Foundation

/// Computes a Return path (ADR-031 §7): from the athlete's position back to a point of the
/// Itinerary they left. Mapbox Directions with the Itineraries' token in the app, a fake in tests.
protocol ReturnPathRouter: Sendable {
    /// Path from `position` to `destination`, both snapped to the network however far they are,
    /// leaving along `bearing` when given. Throws a `RoutingError`, or `CancellationError` when
    /// the task is cancelled.
    func returnPath(
        from position: Coordinate,
        to destination: Coordinate,
        profile: RoutingProfile,
        bearing: Bearing?
    ) async throws -> RoutedReturnPath
}

/// Router answer for a Return path.
struct RoutedReturnPath: Equatable, Sendable {
    /// From the snapped position to the snapped destination.
    let path: [Coordinate]
    /// Length measured by the router.
    let distance: Distance
}
