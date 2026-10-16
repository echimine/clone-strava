import Foundation

/// `APIClient` adapter of `ActivityDetailRepository`: `GET /v1/activities/:id` for any
/// visible Activity (ADR-033 §2), decoded with the generated OpenAPI type (ADR-026).
struct APIActivityDetailRepository: ActivityDetailRepository {
    private typealias DetailResponse = Components.Schemas.ActivityDetailDto_Output

    let apiClient: APIClient

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail {
        do {
            let response: DetailResponse = try await apiClient.get("/v1/activities/\(id)")
            return response.model(id: id)
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

private extension Components.Schemas.ActivityDetailDto_Output {
    func model(id: ActivityID) -> ActivityDetail {
        ActivityDetail(
            id: id,
            title: title,
            description: description.flatMap { $0.isEmpty ? nil : $0 },
            sport: SportType(code: sportTypeCode),
            visibility: ActivityVisibility(rawValue: visibility.rawValue) ?? .private,
            startedAt: startedAt,
            locationName: locationName,
            stats: stats.map {
                ActivityStats(
                    distance: $0.distanceM.map { Distance(meters: $0) },
                    movingTime: $0.movingTimeS.map { .seconds($0) },
                    elapsedTime: $0.elapsedTimeS.map { .seconds($0) },
                    elevationGain: $0.elevationGainM,
                    avgSpeedMs: $0.avgSpeedMs,
                    maxSpeedMs: $0.maxSpeedMs,
                    avgHeartRate: $0.avgHeartRate,
                    maxHeartRate: $0.maxHeartRate,
                    calories: $0.calories
                )
            },
            route: map.map { EncodedPolyline(value: $0.polyline, precision: Int($0.precision)) },
            author: ActivityAuthor(
                id: author.id,
                displayName: author.displayName,
                avatarURL: author.avatarUrl.flatMap(URL.init(string:))
            ),
            engagement: ActivityEngagement(
                kudosCount: engagement.kudosCount,
                commentCount: engagement.commentCount,
                viewerHasKudoed: engagement.viewerHasKudoed
            ),
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
