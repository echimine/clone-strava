import Foundation

/// `APIClient` adapter of `ModerationRepository`: `POST /v1/reports`, `PUT` / `DELETE
/// /v1/me/blocks/:id` and `GET /v1/me/blocks` (ADR-038 §8, §9), decoded with the generated
/// OpenAPI types (ADR-026).
struct APIModerationRepository: ModerationRepository {
    private typealias ReportResponse = Components.Schemas.CreateReportResponseDto_Output
    private typealias BlocksResponse = Components.Schemas.BlockedAthleteListResponseDto_Output

    private struct ReportBody: Encodable {
        let targetType: String
        let targetId: String
        let reason: String
        let note: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    let apiClient: APIClient

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws(ModerationError) -> ReportOutcome {
        let body = ReportBody(targetType: target.kind.rawValue, targetId: target.targetId, reason: reason.rawValue, note: note)
        let (_, http): (ReportResponse, HTTPURLResponse) = try await call { () async throws(APIError) in
            try await apiClient.sendWithHeaders(method: "POST", path: "/v1/reports", body: body)
        }
        return http.statusCode == 201 ? .reported : .alreadyReported
    }

    func block(_ athleteId: String) async throws(ModerationError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: "PUT", path: "/v1/me/blocks/\(athleteId)")
        }
    }

    func unblock(_ athleteId: String) async throws(ModerationError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: "DELETE", path: "/v1/me/blocks/\(athleteId)")
        }
    }

    func blockedAthletes() async throws(ModerationError) -> [BlockedAthlete] {
        let response: BlocksResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/me/blocks")
        }
        return response.items.map {
            BlockedAthlete(
                athlete: ActivityAuthor(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                blockedAt: $0.blockedAt
            )
        }
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(ModerationError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(404, _): throw .notFound
            case .http(429, _): throw .rateLimited
            case .http(_, let body):
                throw .server(code: body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code)
            case .decoding: throw .server(code: nil)
            case .transport: throw .network
            }
        }
    }
}
