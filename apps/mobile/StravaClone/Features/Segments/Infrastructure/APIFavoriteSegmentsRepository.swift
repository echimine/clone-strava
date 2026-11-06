import Foundation

/// `APIClient` adapter of `FavoriteSegmentsRepository`: `GET /v1/me/segment-favorites`.
struct APIFavoriteSegmentsRepository: FavoriteSegmentsRepository {
    private struct Item: Decodable {
        let id: String
        let sport: String
        let name: String
        let verified: Bool
        let distanceM: Double
        let avgGradePct: Double
        let climbCategory: String?
        let myBestTimeS: Int?
    }

    private struct Response: Decodable {
        let items: [Item]
        let nextCursor: String?
    }

    let apiClient: APIClient
    var pageSize = 20

    func page(after cursor: String?) async throws(SegmentError) -> FavoriteSegmentsPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: Response = try await SegmentAPIError.call { () async throws(APIError) in
            try await apiClient.get("/v1/me/segment-favorites", query: query)
        }
        return FavoriteSegmentsPage(
            items: response.items.compactMap { item in
                guard let sport = SegmentSport(rawValue: item.sport) else { return nil }
                return FavoriteSegment(
                    id: item.id,
                    sport: sport,
                    name: item.name,
                    isVerified: item.verified,
                    distance: Distance(meters: item.distanceM),
                    averageGrade: item.avgGradePct,
                    climbCategory: item.climbCategory.flatMap(ClimbCategory.init(rawValue:)),
                    myBestTime: item.myBestTimeS.map { .seconds($0) }
                )
            },
            nextCursor: response.nextCursor
        )
    }
}
