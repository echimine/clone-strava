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

/// Asks the API for a short-lived grant to subscribe to one topic (`POST /v1/realtime/grants`,
/// ADR-034 §5). Checked once, at `sub`: request it right before subscribing.
struct RealtimeGrantProvider: Sendable {
    let apiClient: APIClient

    func grant(topic: String) async throws(APIError) -> String {
        let response: Components.Schemas.RealtimeGrantResponseDto_Output = try await apiClient.send(
            method: "POST",
            path: "/v1/realtime/grants",
            body: Components.Schemas.RealtimeGrantRequestDto(topic: topic)
        )
        return response.grant
    }
}
