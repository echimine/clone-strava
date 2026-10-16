import Foundation

/// The shared realtime connection as a feature sees it (ADR-010): its events, each
/// (re)connection, and control messages sent on it. `WebSocketClient` in the app, faked in tests.
protocol RealtimeChannel: Sendable {
    func events() async -> AsyncStream<RealtimeEvent>
    /// One value per (re)connection, once the token's topics are subscribed.
    func connections() async -> AsyncStream<Void>
    /// Sends a control message (`sub`, `unsub`) on the open connection; `false` when there is
    /// none: the next connection is the time to send it again.
    func send(_ message: String) async -> Bool
}
