import Foundation

/// The app's single GPS source (ADR-006, ADR-027): Core Location in the app,
/// a simulated provider in tests. Multi-subscriber: each call returns a new stream,
/// updates run while at least one stream is alive.
protocol LocationProvider: Sendable {
    /// GPS fixes; replays the last known fix to a new subscriber (the map puck).
    func samples() async -> AsyncStream<LocationSample>
    /// Every update of the GPS, with or without a position, never replayed and never dropped
    /// (the Recording, ADR-031 §3).
    func updates() async -> AsyncStream<LocationUpdate>
    /// Compass heading in degrees from north, for the map puck.
    func headings() async -> AsyncStream<Double>
    /// Keeps fixes flowing with the screen locked (Recording only).
    func beginBackgroundTracking() async
    func endBackgroundTracking() async
}

/// One update of the GPS stream (ADR-031 §3): a position (with speed and course) or none,
/// whether the device is stationary, and what went wrong if anything.
struct LocationUpdate: Equatable, Sendable {
    var sample: LocationSample?
    /// Core Location's `isStationary`: no movement detected, updates may pause.
    var isStationary = false
    var issue: LocationIssue?
}

enum LocationIssue: Equatable, Sendable {
    /// Location access denied or restricted.
    case denied
    /// Approximate location only.
    case accuracyLimited
    /// No position can be determined right now.
    case unavailable
    /// The update loop failed with a Core Location error.
    case failed(String)
}
