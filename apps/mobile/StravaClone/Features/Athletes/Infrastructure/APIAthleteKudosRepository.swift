import Foundation

/// `APIClient` adapter of `AthleteKudosRepository`: `PUT` and `DELETE /v1/activities/:id/kudos`
/// (ADR-029), decoded with the generated OpenAPI types (ADR-026).
struct APIAthleteKudosRepository: AthleteKudosRepository {
    private typealias KudosResponse = Components.Schemas.KudosResponseDto_Output

    let apiClient: APIClient

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(AthleteError) -> KudosState {
        let response: KudosResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(method: given ? "PUT" : "DELETE", path: "/v1/activities/\(activityId)/kudos")
        }
        return KudosState(kudosCount: response.kudosCount, viewerHasKudoed: response.viewerHasKudoed)
    }
}
