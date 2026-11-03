import Foundation

/// `APIClient` adapter of `AthleteRepository`: `GET /v1/athletes/:id`, `GET
/// /v1/athletes/:id/activities` (the feed's response, ADR-036 §3) and `GET
/// /v1/athletes/:id/stats` (ADR-036 §4), decoded with the generated OpenAPI types (ADR-026).
struct APIAthleteRepository: AthleteRepository {
    private typealias ProfileResponse = Components.Schemas.AthleteProfileResponseDto_Output
    /// `GET /v1/athletes/:id/activities` returns the feed's format: decoded with the feed's type,
    /// so both lists share one mapping (`OpenAPIContractTests` checks the two schemas agree).
    private typealias ActivitiesResponse = Components.Schemas.FeedResponseDto_Output
    private typealias StatsResponse = Components.Schemas.AthleteStatsResponseDto_Output

    let apiClient: APIClient
    var pageSize = 20

    func profile(of athleteId: String) async throws(AthleteError) -> AthleteProfile {
        let response: ProfileResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)")
        }
        return response.model
    }

    func activities(of athleteId: String, cursor: String?) async throws(AthleteError) -> FeedPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: ActivitiesResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)/activities", query: query)
        }
        return response.page
    }

    func yearToDateDistance(of athleteId: String) async throws(AthleteError) -> Distance {
        let response: StatsResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)/stats")
        }
        return Distance(meters: response.yearToDate.distanceM)
    }
}

/// Maps `APIError` to `AthleteError`, for every adapter that reads or changes a profile.
enum APIAthleteErrors {
    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    static func call<T>(_ operation: () async throws(APIError) -> T) async throws(AthleteError) -> T {
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

extension Components.Schemas.AthleteProfileResponseDto_Output.athletePayload {
    var identity: ActivityAuthor {
        ActivityAuthor(id: id, displayName: displayName, avatarURL: avatarUrl.flatMap(URL.init(string:)))
    }
}

private extension Components.Schemas.AthleteProfileResponseDto_Output {
    var model: AthleteProfile {
        AthleteProfile(
            athlete: athlete.identity,
            activityCount: activityCount,
            streakWeeks: streakWeeks,
            followerCount: followerCount,
            followingCount: followingCount,
            viewerFollowStatus: viewerFollowStatus.flatMap { FollowStatus(rawValue: $0.rawValue) },
            followersYouKnow: followersYouKnow.map {
                ActivityAuthor(id: $0.id, displayName: $0.displayName, avatarURL: $0.avatarUrl.flatMap(URL.init(string:)))
            },
            practicedSports: practicedSports.map(SportType.init(code:)),
            approveFollowers: approveFollowers,
            pendingFollowRequestCount: pendingFollowRequestCount,
            itineraryCount: itineraryCount
        )
    }
}
