import Foundation
@testable import StravaClone

/// Hand-written `ReturnPathRouter` (ADR-025 §3): records every call and answers a straight
/// path from the position to the destination, 20 % longer than the crow flies, by default.
/// `hold()` suspends answers until `release()`, to observe a request in flight.
actor FakeReturnPathRouter: ReturnPathRouter {
    struct Call: Equatable, Sendable {
        let position: Coordinate
        let destination: Coordinate
        let profile: RoutingProfile
        let bearing: Bearing?
    }

    private(set) var calls: [Call] = []
    private var answer: @Sendable (Coordinate, Coordinate) throws -> RoutedReturnPath = FakeReturnPathRouter.straight
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    func answer(with answer: @escaping @Sendable (Coordinate, Coordinate) throws -> RoutedReturnPath) {
        self.answer = answer
    }

    func fail(with error: RoutingError) {
        answer = { _, _ in throw error }
    }

    func hold() {
        isHolding = true
    }

    func release() {
        isHolding = false
        let continuations = held
        held = []
        continuations.forEach { $0.resume() }
    }

    /// Waits up to `timeout` for `count` calls in total, returns the calls.
    @discardableResult
    func waitForCalls(_ count: Int, timeout: Duration = .seconds(2)) async -> [Call] {
        let deadline = ContinuousClock.now + timeout
        while calls.count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return calls
    }

    func returnPath(
        from position: Coordinate,
        to destination: Coordinate,
        profile: RoutingProfile,
        bearing: Bearing?
    ) async throws -> RoutedReturnPath {
        calls.append(Call(position: position, destination: destination, profile: profile, bearing: bearing))
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        return try answer(position, destination)
    }

    @Sendable static func straight(_ position: Coordinate, _ destination: Coordinate) -> RoutedReturnPath {
        RoutedReturnPath(path: [position, destination], distance: Distance(meters: position.distance(to: destination).meters * 1.2))
    }
}
