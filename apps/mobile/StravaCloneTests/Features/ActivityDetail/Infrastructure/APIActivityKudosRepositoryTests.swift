import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class KudosURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `GET /v1/activities/:id/kudos` (ADR-034 §1) through the generated `ListKudosResponseDto_Output`,
/// and `PUT`/`DELETE` of the viewer's kudos (ADR-029).
@Suite(.serialized)
struct APIActivityKudosRepositoryTests {
    private let activityId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private var id: ActivityID { ActivityID(UUID(uuidString: activityId)!) }

    private func makeRepository() -> APIActivityKudosRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KudosURLProtocolStub.self]
        let authSession = AuthSession(service: "test.activityKudos.\(UUID())")
        authSession.clear()
        KudosURLProtocolStub.requests.value = []
        return APIActivityKudosRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    @Test func decodesAPageOfGivers() async throws {
        let repository = makeRepository()
        KudosURLProtocolStub.handler.value = { _ in
            (200, Data("""
            {
              "items": [
                { "athlete": { "id": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11", "displayName": "Camille Martin", "avatarUrl": "https://cdn.test/c.png" },
                  "givenAt": "2026-10-16T10:00:00.123Z" },
                { "athlete": { "id": "1c6b6d2f-2a5f-4d66-8e7f-1e4a9a7f3b22", "displayName": "Léo", "avatarUrl": null },
                  "givenAt": "2026-10-16T09:59:00.000Z" }
              ],
              "nextCursor": "abc"
            }
            """.utf8))
        }

        let page = try await repository.kudos(activityId: id, cursor: "prev", limit: 5)

        let url = try #require(KudosURLProtocolStub.requests.value.first?.url)
        #expect(url.path == "/v1/activities/\(activityId)/kudos")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(query) == [URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "cursor", value: "prev")])
        #expect(page.nextCursor == "abc")
        #expect(page.givers.map(\.athlete) == [
            ActivityAuthor(
                id: "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11",
                displayName: "Camille Martin",
                avatarURL: URL(string: "https://cdn.test/c.png")
            ),
            ActivityAuthor(id: "1c6b6d2f-2a5f-4d66-8e7f-1e4a9a7f3b22", displayName: "Léo", avatarURL: nil),
        ])
        #expect(abs((page.givers.first?.givenAt.timeIntervalSince1970 ?? 0) - 1_792_144_800.123) < 0.000_5)
    }

    @Test func givesAndRemovesTheViewersKudos() async throws {
        let repository = makeRepository()
        KudosURLProtocolStub.handler.value = { [activityId] request in
            let given = request.httpMethod == "PUT"
            return (200, Data("""
            { "activityId": "\(activityId)", "kudosCount": \(given ? 4 : 3), "viewerHasKudoed": \(given) }
            """.utf8))
        }

        #expect(try await repository.setKudos(true, activityId: id) == KudosState(kudosCount: 4, viewerHasKudoed: true))
        #expect(try await repository.setKudos(false, activityId: id) == KudosState(kudosCount: 3, viewerHasKudoed: false))
        #expect(KudosURLProtocolStub.requests.value.map(\.httpMethod) == ["PUT", "DELETE"])
        #expect(KudosURLProtocolStub.requests.value.map(\.url?.path) == Array(repeating: "/v1/activities/\(activityId)/kudos", count: 2))
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()

        KudosURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"activity_not_found","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.notFound) {
            try await repository.kudos(activityId: id, cursor: nil, limit: 5)
        }

        KudosURLProtocolStub.handler.value = { _ in
            (422, Data(#"{"error":{"code":"invalid_cursor","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.server(code: "invalid_cursor")) {
            try await repository.kudos(activityId: id, cursor: "bad", limit: 5)
        }
    }
}
