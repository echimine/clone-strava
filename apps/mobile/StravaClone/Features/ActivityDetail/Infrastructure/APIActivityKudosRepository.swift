import Foundation

/// `APIClient` adapter of `ActivityKudosRepository`: `GET /v1/activities/:id/kudos`
/// (ADR-034 §1), decoded with the generated OpenAPI type (ADR-026), and `PUT`/`DELETE` of the
/// viewer's kudos (ADR-029).
struct APIActivityKudosRepository: ActivityKudosRepository {
    private typealias ListResponse = Components.Schemas.ListKudosResponseDto_Output
    private typealias StateResponse = Components.Schemas.KudosResponseDto_Output

    let apiClient: APIClient

    func kudos(activityId: ActivityID, cursor: String?, limit: Int) async throws(ActivityDetailError) -> KudosPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: ListResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/activities/\(activityId)/kudos", query: query)
        }
        return KudosPage(
            givers: response.items.map { item in
                KudosGiver(
                    athlete: ActivityAuthor(
                        id: item.athlete.id,
                        displayName: item.athlete.displayName,
                        avatarURL: item.athlete.avatarUrl.flatMap(URL.init(string:))
                    ),
                    givenAt: item.givenAt
                )
            },
            nextCursor: response.nextCursor
        )
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(ActivityDetailError) -> KudosState {
        let response: StateResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: given ? "PUT" : "DELETE", path: "/v1/activities/\(activityId)/kudos")
        }
        return KudosState(kudosCount: response.kudosCount, viewerHasKudoed: response.viewerHasKudoed)
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(ActivityDetailError) -> T {
        do {
            return try await operation()
        } catch {
            throw ActivityDetailError(error)
        }
    }
}
