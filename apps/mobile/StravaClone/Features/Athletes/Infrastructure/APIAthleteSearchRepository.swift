import Foundation

/// `APIClient` adapter of `AthleteSearchRepository`: `GET /v1/athletes/search?q=` (ADR-036 §2).
struct APIAthleteSearchRepository: AthleteSearchRepository {
    private typealias SearchResponse = Components.Schemas.AthleteSearchResponseDto_Output

    let apiClient: APIClient

    func search(_ query: String) async throws(AthleteError) -> [AthleteListItem] {
        let response: SearchResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/search", query: [URLQueryItem(name: "q", value: query)])
        }
        return response.items.map {
            AthleteListItem(
                athlete: ActivityAuthor(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                viewerFollowStatus: FollowStatus(rawValue: $0.viewerFollowStatus.rawValue)
            )
        }
    }
}
