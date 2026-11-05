import Foundation

/// `APIClient` adapter of `StarredSegmentsRepository`: `GET /v1/me/segment-favorites`.
struct APIStarredSegmentsRepository: StarredSegmentsRepository {
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

    func page(after cursor: String?) async throws(StarredSegmentsError) -> StarredSegmentsPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: Response
        do {
            response = try await apiClient.get("/v1/me/segment-favorites", query: query)
        } catch .offline {
            throw .offline
        } catch {
            throw .unavailable
        }
        return StarredSegmentsPage(
            items: response.items.compactMap { item in
                guard let sport = SegmentSport(rawValue: item.sport) else { return nil }
                return StarredSegment(
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
