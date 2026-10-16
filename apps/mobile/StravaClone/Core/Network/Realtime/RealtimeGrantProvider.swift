import Foundation

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
