import Foundation

/// `APIClient` adapter of `ProfileRepository`: `PATCH /v1/me/profile` and `PUT
/// /v1/me/follow-settings` (ADR-036 §1, §3), with the generated OpenAPI types (ADR-026).
struct APIProfileRepository: ProfileRepository {
    private typealias RenameRequest = Components.Schemas.UpdateProfileRequestDto
    private typealias RenameResponse = Components.Schemas.UpdateProfileResponseDto_Output
    private typealias SettingsRequest = Components.Schemas.FollowSettingsDto
    private typealias SettingsResponse = Components.Schemas.FollowSettingsDto_Output

    let apiClient: APIClient

    func rename(_ name: ProfileName) async throws(AthleteError) -> ActivityAuthor {
        let response: RenameResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(
                method: "PATCH",
                path: "/v1/me/profile",
                body: RenameRequest(firstName: name.firstName, lastName: name.lastName)
            )
        }
        let athlete = response.athlete
        return ActivityAuthor(id: athlete.id, displayName: athlete.displayName, avatarUrl: athlete.avatarUrl)
    }

    func setApproveFollowers(_ approve: Bool) async throws(AthleteError) -> Bool {
        let response: SettingsResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(
                method: "PUT",
                path: "/v1/me/follow-settings",
                body: SettingsRequest(approveFollowers: approve)
            )
        }
        return response.approveFollowers
    }
}
