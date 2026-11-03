import Foundation

/// `APIClient` adapter of `FeedRepository`: `GET /v1/feed`, `PUT`/`DELETE
/// /v1/activities/:id/kudos` (ADR-029) and the most recent givers of `GET
/// /v1/activities/:id/kudos` (ADR-034 §1), decoded with the generated OpenAPI types (ADR-026).
struct APIFeedRepository: FeedRepository {
    private typealias FeedResponse = Components.Schemas.FeedResponseDto_Output
    private typealias KudosResponse = Components.Schemas.KudosResponseDto_Output
    private typealias KudosListResponse = Components.Schemas.ListKudosResponseDto_Output

    /// The card shows at most this many kudos avatars (ADR-036 §5).
    static let recentKudosLimit = 3

    let apiClient: APIClient
    var pageSize = 20

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func page(cursor: String?) async throws(FeedError) -> FeedPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: FeedResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/feed", query: query)
        }
        return FeedPage(posts: response.items.compactMap(\.model), nextCursor: response.nextCursor)
    }

    func recentKudos(activityId: ActivityID) async throws(FeedError) -> [ActivityAuthor] {
        let response: KudosListResponse = try await call { () async throws(APIError) in
            try await apiClient.get(
                "/v1/activities/\(activityId)/kudos",
                query: [URLQueryItem(name: "limit", value: String(Self.recentKudosLimit))]
            )
        }
        return response.items.prefix(Self.recentKudosLimit).map {
            ActivityAuthor(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarURL: $0.athlete.avatarUrl.flatMap(URL.init(string:)))
        }
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(FeedError) -> KudosState {
        let response: KudosResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: given ? "PUT" : "DELETE", path: "/v1/activities/\(activityId)/kudos")
        }
        return KudosState(kudosCount: response.kudosCount, viewerHasKudoed: response.viewerHasKudoed)
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(FeedError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(404, _): throw .notFound
            case .http(_, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                throw .server(code: code)
            case .decoding: throw .server(code: nil)
            case .transport: throw .network
            }
        }
    }
}

private extension Components.Schemas.FeedResponseDto_Output.itemsPayloadPayload {
    /// Nil for an item whose id is not a UUID, which the API never sends.
    var model: ActivityPost? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ActivityPost(
            id: ActivityID(uuid),
            title: title,
            sport: SportType(code: sportTypeCode),
            startedAt: startedAt,
            locationName: locationName,
            distance: stats.distanceM.map { Distance(meters: $0) },
            movingTime: stats.movingTimeS.map { .seconds($0) },
            elevationGain: stats.elevationGainM,
            avgSpeedMs: stats.avgSpeedMs,
            route: map.map { EncodedPolyline(value: $0.polyline, precision: Int($0.precision)) },
            routeTrimmed: routeTrimmed,
            author: ActivityAuthor(id: author.id, displayName: author.displayName, avatarURL: author.avatarUrl.flatMap(URL.init(string:))),
            engagement: ActivityEngagement(
                kudosCount: engagement.kudosCount,
                commentCount: engagement.commentCount,
                viewerHasKudoed: engagement.viewerHasKudoed
            ),
            recentKudos: recentKudos.map {
                ActivityAuthor(id: $0.id, displayName: $0.displayName, avatarURL: $0.avatarUrl.flatMap(URL.init(string:)))
            },
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
