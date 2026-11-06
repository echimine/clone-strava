import Foundation

/// The Participant token the Live SDK asks for at each connection (`POST
/// /v1/live/participant-token`): a 5 min JWT our API signs for the signed-in athlete.
struct APILiveParticipantTokenProvider: Sendable {
    let apiClient: APIClient

    private struct TokenResponse: Decodable {
        let token: String
    }

    func token() async throws(APIError) -> String {
        let response: TokenResponse = try await apiClient.send(
            method: "POST",
            path: "/v1/live/participant-token",
            body: String?.none
        )
        return response.token
    }
}
