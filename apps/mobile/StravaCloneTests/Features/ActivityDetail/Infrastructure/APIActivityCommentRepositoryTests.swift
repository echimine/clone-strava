import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIActivityDetailRepositoryTests`: suites run in parallel.
private final class CommentsURLProtocolStub: URLProtocol, @unchecked Sendable {
    struct Recorded: Equatable {
        let method: String
        let path: String
        let query: String?
        let body: Data?
    }

    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[Recorded]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(Recorded(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            query: request.url?.query,
            body: request.httpBody ?? request.httpBodyStream.map(Self.read)
        ))
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// `…/v1/activities/:id/comments` (ADR-034 §3) through the generated OpenAPI types.
@Suite(.serialized)
struct APIActivityCommentRepositoryTests {
    private let activityPath = "/v1/activities/7c9e6679-7425-40de-944b-e07fc1f90ae7/comments"
    private let activityId = ActivityID(UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!)
    private let commentId = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
    private let commentIdString = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

    private func makeRepository() -> APIActivityCommentRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommentsURLProtocolStub.self]
        let authSession = AuthSession(service: "test.activityComments.\(UUID())")
        authSession.clear()
        CommentsURLProtocolStub.requests.value = []
        return APIActivityCommentRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func commentJSON(body: String = "Belle sortie", updatedAt: String = "null") -> String {
        """
        {
          "id": "\(commentIdString)", "body": "\(body)",
          "createdAt": "2026-10-02T12:32:00.123Z", "updatedAt": \(updatedAt),
          "author": { "id": "u2", "displayName": "Léa Durand", "avatarUrl": "https://cdn.test/l.png" },
          "viewerCanEdit": false, "viewerCanDelete": true
        }
        """
    }

    private var expectedComment: ActivityComment {
        ActivityComment(
            id: commentId,
            body: "Belle sortie",
            createdAt: Date(timeIntervalSince1970: 1_790_944_320.123),
            updatedAt: nil,
            author: ActivityAuthor(id: "u2", displayName: "Léa Durand", avatarURL: URL(string: "https://cdn.test/l.png")),
            viewerCanEdit: false,
            viewerCanDelete: true
        )
    }

    private func sameComment(_ comment: ActivityComment, _ expected: ActivityComment) -> Bool {
        var comment = comment
        // Milliseconds survive the round trip only approximately.
        guard abs(comment.createdAt.timeIntervalSince(expected.createdAt)) < 0.000_5 else { return false }
        comment = ActivityComment(
            id: comment.id, body: comment.body, createdAt: expected.createdAt, updatedAt: comment.updatedAt,
            author: comment.author, viewerCanEdit: comment.viewerCanEdit, viewerCanDelete: comment.viewerCanDelete
        )
        return comment == expected
    }

    @Test func listsAPageAndTheOlderOnes() async throws {
        let repository = makeRepository()
        let json = Data(#"{ "items": [\#(commentJSON())], "previousCursor": "abc" }"#.utf8)
        CommentsURLProtocolStub.handler.value = { _ in (200, json) }

        let page = try await repository.comments(activityId: activityId, before: nil)
        _ = try await repository.comments(activityId: activityId, before: "abc")

        #expect(page.previousCursor == "abc")
        #expect(page.items.count == 1)
        #expect(sameComment(try #require(page.items.first), expectedComment))
        #expect(CommentsURLProtocolStub.requests.value.map(\.path) == [activityPath, activityPath])
        #expect(CommentsURLProtocolStub.requests.value.map(\.query) == [nil, "before=abc"])
    }

    @Test func fetchesOneComment() async throws {
        let repository = makeRepository()
        let json = Data(commentJSON(updatedAt: #""2026-10-03T08:00:00.000Z""#).utf8)
        CommentsURLProtocolStub.handler.value = { _ in (200, json) }

        let comment = try await repository.comment(activityId: activityId, id: commentId)

        #expect(comment.updatedAt == Date(timeIntervalSince1970: 1_791_014_400))
        #expect(CommentsURLProtocolStub.requests.value.map(\.path) == ["\(activityPath)/\(commentIdString)"])
    }

    @Test func addsUnderTheAppGeneratedId() async throws {
        let repository = makeRepository()
        let json = Data(commentJSON().utf8)
        CommentsURLProtocolStub.handler.value = { _ in (201, json) }

        let comment = try await repository.add(activityId: activityId, id: commentId, body: "Belle sortie")

        #expect(sameComment(comment, expectedComment))
        let request = try #require(CommentsURLProtocolStub.requests.value.first)
        #expect(request.method == "POST")
        #expect(request.path == activityPath)
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(body == ["id": commentIdString, "body": "Belle sortie"])
    }

    @Test func editsAndDeletes() async throws {
        let repository = makeRepository()
        let json = Data(commentJSON(body: "Corrigé", updatedAt: #""2026-10-03T08:00:00.000Z""#).utf8)
        CommentsURLProtocolStub.handler.value = { request in
            request.httpMethod == "DELETE" ? (204, Data()) : (200, json)
        }

        let edited = try await repository.edit(activityId: activityId, id: commentId, body: "Corrigé")
        try await repository.delete(activityId: activityId, id: commentId)

        #expect(edited.body == "Corrigé")
        let requests = CommentsURLProtocolStub.requests.value
        #expect(requests.map(\.method) == ["PATCH", "DELETE"])
        #expect(requests.map(\.path) == ["\(activityPath)/\(commentIdString)", "\(activityPath)/\(commentIdString)"])
        let body = try JSONSerialization.jsonObject(with: try #require(requests.first?.body)) as? [String: String]
        #expect(body == ["body": "Corrigé"])
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()

        CommentsURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"comment_not_found","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityCommentError.notFound) {
            try await repository.comment(activityId: activityId, id: commentId)
        }

        CommentsURLProtocolStub.handler.value = { _ in
            (409, Data(#"{"error":{"code":"comment_id_conflict","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityCommentError.server(code: "comment_id_conflict")) {
            try await repository.add(activityId: activityId, id: commentId, body: "x")
        }

        CommentsURLProtocolStub.handler.value = { _ in (401, Data()) }
        await #expect(throws: ActivityCommentError.unauthorized) {
            try await repository.delete(activityId: activityId, id: commentId)
        }
    }
}
