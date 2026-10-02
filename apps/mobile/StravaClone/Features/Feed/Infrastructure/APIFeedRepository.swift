import Foundation

/// `APIClient` adapter of `FeedRepository`: `GET /v1/feed` and
/// `PUT`/`DELETE /v1/activities/:id/kudos` (ADR-029).
struct APIFeedRepository: FeedRepository {
    let apiClient: APIClient
    var pageSize = 20

    private struct FeedResponse: Decodable {
        let items: [ItemDTO]
        let nextCursor: String?
    }

    private struct ItemDTO: Decodable {
        struct Stats: Decodable {
            let distanceM: Double?
            let movingTimeS: Int?
            let elevationGainM: Double?
        }

        struct MapDTO: Decodable {
            let polyline: String
            let precision: Int
        }

        struct Author: Decodable {
            let id: String
            let displayName: String
            let avatarUrl: String?
        }

        let id: UUID
        let title: String
        let sportTypeCode: String
        let startedAt: Date
        let locationName: String?
        let stats: Stats
        let map: MapDTO?
        let author: Author
        let engagement: EngagementDTO
        let viewerIsAuthor: Bool

        var model: ActivityPost {
            ActivityPost(
                id: ActivityID(id),
                title: title,
                sport: SportType(code: sportTypeCode),
                startedAt: startedAt,
                locationName: locationName,
                distance: stats.distanceM.map { Distance(meters: $0) },
                movingTime: stats.movingTimeS.map { .seconds($0) },
                elevationGain: stats.elevationGainM,
                route: map.map { EncodedPolyline(value: $0.polyline, precision: $0.precision) },
                author: ActivityAuthor(
                    id: author.id,
                    displayName: author.displayName,
                    avatarURL: author.avatarUrl.flatMap(URL.init(string:))
                ),
                engagement: engagement.model,
                viewerIsAuthor: viewerIsAuthor
            )
        }
    }

    private struct EngagementDTO: Decodable {
        let kudosCount: Int
        let commentCount: Int
        let viewerHasKudoed: Bool

        var model: ActivityEngagement {
            ActivityEngagement(kudosCount: kudosCount, commentCount: commentCount, viewerHasKudoed: viewerHasKudoed)
        }
    }

    private struct KudosResponse: Decodable {
        let kudosCount: Int
        let viewerHasKudoed: Bool
    }

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
        return FeedPage(posts: response.items.map(\.model), nextCursor: response.nextCursor)
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
