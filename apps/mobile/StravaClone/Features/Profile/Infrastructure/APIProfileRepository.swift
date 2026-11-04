import Foundation

/// `APIClient` adapter of `ProfileRepository`: `GET` and `PATCH /v1/me/profile` and `PUT
/// /v1/me/follow-settings` (ADR-036 §1, §3), with the generated OpenAPI types (ADR-026).
struct APIProfileRepository: ProfileRepository {
    private typealias EditableResponse = Components.Schemas.EditableProfileResponseDto_Output
    private typealias UpdateRequest = Components.Schemas.UpdateProfileRequestDto
    private typealias UpdateResponse = Components.Schemas.UpdateProfileResponseDto_Output
    private typealias SettingsRequest = Components.Schemas.FollowSettingsDto
    private typealias SettingsResponse = Components.Schemas.FollowSettingsDto_Output

    let apiClient: APIClient

    func editableProfile() async throws(AthleteError) -> EditableProfile {
        let response: EditableResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(method: "GET", path: "/v1/me/profile")
        }
        let profile = response.profile
        return EditableProfile(
            firstName: profile.firstName ?? "",
            lastName: profile.lastName ?? "",
            bio: profile.bio ?? "",
            city: profile.city ?? "",
            countryCode: profile.country,
            mainSport: profile.mainSportCode.map(SportType.init(code:)),
            birthDate: profile.birthDate.flatMap(CalendarDay.init(iso:)),
            gender: profile.gender.flatMap { Gender(rawValue: $0.rawValue) },
            weightKg: profile.weightKg
        )
    }

    /// Bio, Ville and Pays are always sent, so emptying one clears it; a field without a value
    /// is left out and stays as it is.
    func update(_ update: ProfileUpdate) async throws(AthleteError) -> ActivityAuthor {
        let body = UpdateRequest(
            firstName: update.name.firstName,
            lastName: update.name.lastName,
            bio: update.bio,
            city: update.city,
            country: update.countryCode,
            mainSportCode: update.mainSport?.code,
            birthDate: update.birthDate?.iso,
            gender: update.gender.flatMap { UpdateRequest.genderPayload(rawValue: $0.rawValue) },
            weightKg: update.weightKg
        )
        let response: UpdateResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(method: "PATCH", path: "/v1/me/profile", body: body)
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
