import Foundation

/// Fetches the short-lived token that opens the WebSocket (`POST /v1/realtime/token`,
/// ADR-010 §3). A new one is requested for every (re)connection: it lives 60 s.
struct RealtimeTokenProvider: Sendable {
    let apiClient: APIClient

    private struct TokenResponse: Decodable {
        let token: String
    }

    func token() async throws(APIError) -> String {
        let response: TokenResponse = try await apiClient.send(
            method: "POST",
            path: "/v1/realtime/token",
            body: String?.none
        )
        return response.token
    }
}
