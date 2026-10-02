import Foundation

/// The app's single GPS source (ADR-006, ADR-027): Core Location in the app,
/// a simulated provider in tests. Multi-subscriber: each call returns a new stream,
/// updates run while at least one stream is alive.
protocol LocationProvider: Sendable {
    /// GPS fixes; replays the last known fix to a new subscriber.
    func samples() async -> AsyncStream<LocationSample>
    /// Compass heading in degrees from north, for the map puck.
    func headings() async -> AsyncStream<Double>
    /// Keeps fixes flowing with the screen locked (Recording only).
    func beginBackgroundTracking() async
    func endBackgroundTracking() async
}
