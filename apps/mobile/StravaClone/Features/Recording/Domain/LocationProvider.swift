import Foundation

/// GPS port of the Recording domain (ADR-006): Core Location in the app,
/// a simulated provider in tests and in the simulator.
protocol LocationProvider: Sendable {
    func start() async -> AsyncStream<LocationSample>
    func stop() async
}
