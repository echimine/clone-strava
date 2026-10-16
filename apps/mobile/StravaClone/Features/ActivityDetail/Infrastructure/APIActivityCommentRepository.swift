import Foundation

/// `APIClient` adapter of `ActivityCommentRepository`: `…/v1/activities/:id/comments`
/// (ADR-034 §3), decoded with the generated OpenAPI types (ADR-026).
struct APIActivityCommentRepository: ActivityCommentRepository {
    private typealias CommentResponse = Components.Schemas.CommentDto_Output
    private typealias PageResponse = Components.Schemas.ListCommentsResponseDto_Output

    let apiClient: APIClient

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    private func path(_ activityId: ActivityID, _ id: UUID? = nil) -> String {
        let base = "/v1/activities/\(activityId)/comments"
        return id.map { "\(base)/\($0.uuidString.lowercased())" } ?? base
    }

    func comments(activityId: ActivityID, before: String?) async throws(ActivityCommentError) -> ActivityCommentsPage {
        let query = before.map { [URLQueryItem(name: "before", value: $0)] } ?? []
        let response: PageResponse = try await call { () throws(APIError) in
            try await apiClient.get(path(activityId), query: query)
        }
        return ActivityCommentsPage(
            items: response.items.compactMap {
                ActivityComment(
                    id: $0.id,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    author: (id: $0.author.id, displayName: $0.author.displayName, avatarUrl: $0.author.avatarUrl),
                    viewerCanEdit: $0.viewerCanEdit,
                    viewerCanDelete: $0.viewerCanDelete
                )
            },
            previousCursor: response.previousCursor
        )
    }

    func comment(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) -> ActivityComment {
        try Self.model(try await call { () throws(APIError) -> CommentResponse in
            try await apiClient.get(path(activityId, id))
        })
    }

    func add(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        let request = Components.Schemas.CreateCommentRequestDto(id: id.uuidString.lowercased(), body: body)
        return try Self.model(try await call { () throws(APIError) -> CommentResponse in
            try await apiClient.send(method: "POST", path: path(activityId), body: request)
        })
    }

    func edit(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        let request = Components.Schemas.UpdateCommentRequestDto(body: body)
        return try Self.model(try await call { () throws(APIError) -> CommentResponse in
            try await apiClient.send(method: "PATCH", path: path(activityId, id), body: request)
        })
    }

    func delete(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) {
        let _: NoContent = try await call { () throws(APIError) in
            try await apiClient.send(method: "DELETE", path: path(activityId, id))
        }
    }

    private static func model(_ response: CommentResponse) throws(ActivityCommentError) -> ActivityComment {
        guard let comment = ActivityComment(
            id: response.id,
            body: response.body,
            createdAt: response.createdAt,
            updatedAt: response.updatedAt,
            author: (id: response.author.id, displayName: response.author.displayName, avatarUrl: response.author.avatarUrl),
            viewerCanEdit: response.viewerCanEdit,
            viewerCanDelete: response.viewerCanDelete
        ) else { throw .server(code: nil) }
        return comment
    }

    private func call<Response>(_ request: () async throws(APIError) -> Response) async throws(ActivityCommentError) -> Response {
        do {
            return try await request()
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

private extension ActivityComment {
    /// From either generated shape (list item or single comment); nil on an id that is not a UUID.
    init?(
        id: String,
        body: String,
        createdAt: Date,
        updatedAt: Date?,
        author: (id: String, displayName: String, avatarUrl: String?),
        viewerCanEdit: Bool,
        viewerCanDelete: Bool
    ) {
        guard let uuid = UUID(uuidString: id) else { return nil }
        self.init(
            id: uuid,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            author: ActivityAuthor(
                id: author.id,
                displayName: author.displayName,
                avatarURL: author.avatarUrl.flatMap(URL.init(string:))
            ),
            viewerCanEdit: viewerCanEdit,
            viewerCanDelete: viewerCanDelete
        )
    }
}
