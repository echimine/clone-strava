import Foundation
@testable import StravaClone

/// Hand-written `ItineraryRouter` (ADR-025 §3): records every call and answers with a
/// fake road network by default. The network is a grid of 0.001° cells: a Waypoint snaps
/// to the nearest grid node, and a Leg turns once at the corner `(start.lat, end.lon)`.
/// `hold()` suspends answers until `release()`, to observe in-flight states and races.
actor FakeItineraryRouter: ItineraryRouter {
    struct Call: Equatable, Sendable {
        let waypoints: [Coordinate]
        let profile: RoutingProfile
    }

    private(set) var calls: [Call] = []
    private var answer: @Sendable ([Coordinate]) throws -> RoutedPath = FakeItineraryRouter.gridPath
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    /// Replaces the default grid network, e.g. to throw a `RoutingError`.
    func answer(with answer: @escaping @Sendable ([Coordinate]) throws -> RoutedPath) {
        self.answer = answer
    }

    func fail(with error: RoutingError) {
        answer = { _ in throw error }
    }

    func hold() {
        isHolding = true
    }

    /// Stops holding and lets every suspended call answer.
    func release() {
        isHolding = false
        let continuations = held
        held = []
        continuations.forEach { $0.resume() }
    }

    /// Waits until the router has received `count` calls in total.
    func waitForCalls(_ count: Int) async {
        while calls.count < count {
            await Task.yield()
        }
    }

    func path(through waypoints: [Coordinate], profile: RoutingProfile) async throws -> RoutedPath {
        calls.append(Call(waypoints: waypoints, profile: profile))
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        return try answer(waypoints)
    }

    // MARK: Fake network

    static func snap(_ coordinate: Coordinate) -> Coordinate {
        Coordinate(
            latitude: (coordinate.latitude * 1_000).rounded() / 1_000,
            longitude: (coordinate.longitude * 1_000).rounded() / 1_000
        )
    }

    @Sendable static func gridPath(_ waypoints: [Coordinate]) -> RoutedPath {
        let snapped = waypoints.map(snap)
        let legs = zip(snapped, snapped.dropFirst()).map { start, end in
            [start, Coordinate(latitude: start.latitude, longitude: end.longitude), end]
        }
        return RoutedPath(waypoints: snapped, legs: legs)
    }
}
