import Foundation

/// `APIClient` adapter of `FollowRepository`: `PUT` and `DELETE /v1/athletes/:id/follow`
/// (ADR-036 §1), decoded with the generated OpenAPI types (ADR-026).
struct APIFollowRepository: FollowRepository {
    private typealias FollowResponse = Components.Schemas.FollowResponseDto_Output

    let apiClient: APIClient

    func follow(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await send("PUT", athleteId)
    }

    func unfollow(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await send("DELETE", athleteId)
    }

    private func send(_ method: String, _ athleteId: String) async throws(AthleteError) -> FollowChange {
        let response: FollowResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(method: method, path: "/v1/athletes/\(athleteId)/follow")
        }
        return FollowChange(
            athleteId: response.athleteId,
            status: FollowStatus(rawValue: response.viewerFollowStatus.rawValue) ?? .none,
            followerCount: response.followerCount
        )
    }
}
