import Foundation

/// `APIClient` adapter of `FollowListRepository` (ADR-036 §1): `GET /v1/athletes/:id/followers`
/// and `following`, `/v1/me/follow-requests` and `DELETE /v1/me/followers/:id`, decoded with
/// the generated OpenAPI types (ADR-026).
struct APIFollowListRepository: FollowListRepository {
    private typealias ListResponse = Components.Schemas.FollowListResponseDto_Output
    private typealias RequestsResponse = Components.Schemas.FollowRequestListResponseDto_Output

    let apiClient: APIClient
    var pageSize = 20

    func list(_ list: AthleteFollowsRequest.Kind, of athleteId: String, cursor: String?) async throws(AthleteError) -> AthleteListPage {
        let segment = switch list {
        case .followers: "followers"
        case .following: "following"
        }
        let response: ListResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)/\(segment)", query: query(cursor))
        }
        return AthleteListPage(
            items: response.items.map {
                AthleteListItem(
                    athlete: ActivityAuthor(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                    viewerFollowStatus: $0.viewerFollowStatus.flatMap { FollowStatus(rawValue: $0.rawValue) }
                )
            },
            nextCursor: response.nextCursor
        )
    }

    func followRequests(cursor: String?) async throws(AthleteError) -> FollowRequestPage {
        let response: RequestsResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/me/follow-requests", query: query(cursor))
        }
        return FollowRequestPage(
            items: response.items.map {
                FollowRequest(
                    athlete: ActivityAuthor(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                    viewerFollowStatus: $0.viewerFollowStatus.flatMap { FollowStatus(rawValue: $0.rawValue) },
                    requestedAt: $0.requestedAt
                )
            },
            nextCursor: response.nextCursor
        )
    }

    func acceptRequest(from followerId: String) async throws(AthleteError) {
        try await send("PUT", "/v1/me/follow-requests/\(followerId)")
    }

    func refuseRequest(from followerId: String) async throws(AthleteError) {
        try await send("DELETE", "/v1/me/follow-requests/\(followerId)")
    }

    func removeFollower(_ followerId: String) async throws(AthleteError) {
        try await send("DELETE", "/v1/me/followers/\(followerId)")
    }

    private func query(_ cursor: String?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return query
    }

    private func send(_ method: String, _ path: String) async throws(AthleteError) {
        let _: NoContent = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.send(method: method, path: path)
        }
    }
}
