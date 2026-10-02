import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIActivityImportRepositoryTests`: suites run in parallel.
private final class FeedURLProtocolStub: URLProtocol, @unchecked Sendable {
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

@Suite(.serialized)
struct APIFeedRepositoryTests {
    private let activityId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private func makeRepository() -> APIFeedRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]
        let authSession = AuthSession(service: "test.feed.\(UUID())")
        authSession.clear()
        FeedURLProtocolStub.requests.value = []
        return APIFeedRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private var feedJSON: Data {
        Data("""
        {
          "items": [{
            "id": "\(activityId)",
            "title": "Sortie du matin",
            "sportTypeCode": "ride",
            "startedAt": "2026-10-02T12:32:00.123Z",
            "visibility": "public",
            "locationName": "Annecy, Haute-Savoie",
            "stats": { "distanceM": 42195.5, "movingTimeS": 5400, "elapsedTimeS": 5600, "elevationGainM": null },
            "map": { "polyline": "_p~iF~ps|U_ulLnnqC", "precision": 5 },
            "author": { "id": "u1", "displayName": "Camille Martin", "avatarUrl": "https://cdn.test/a.png" },
            "engagement": { "kudosCount": 3, "commentCount": 1, "viewerHasKudoed": true },
            "viewerIsAuthor": false
          }],
          "nextCursor": "abc"
        }
        """.utf8)
    }

    @Test func decodesAPageWithMillisecondDates() async throws {
        let repository = makeRepository()
        let json = feedJSON
        FeedURLProtocolStub.handler.value = { _ in (200, json) }

        let page = try await repository.page(cursor: "prev")

        let request = try #require(FeedURLProtocolStub.requests.value.first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/feed")
        #expect(components.queryItems == [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "cursor", value: "prev")])

        #expect(page.nextCursor == "abc")
        let post = try #require(page.posts.first)
        #expect(post.id.description == activityId)
        #expect(post.sport == .ride)
        #expect(abs(post.startedAt.timeIntervalSince1970 - 1_790_944_320.123) < 0.000_5)
        #expect(post.distance == Distance(meters: 42_195.5))
        #expect(post.movingTime == .seconds(5_400))
        #expect(post.elevationGain == nil)
        #expect(post.route == EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC"))
        #expect(post.author.avatarURL == URL(string: "https://cdn.test/a.png"))
        #expect(post.engagement == ActivityEngagement(kudosCount: 3, commentCount: 1, viewerHasKudoed: true))
    }

    @Test func givesAndRemovesKudos() async throws {
        let repository = makeRepository()
        FeedURLProtocolStub.handler.value = { request in
            let given = request.httpMethod == "PUT"
            return (200, Data(#"{"activityId":"\#(activityId)","kudosCount":\#(given ? 4 : 3),"viewerHasKudoed":\#(given)}"#.utf8))
        }
        let id = ActivityID(UUID(uuidString: activityId)!)

        #expect(try await repository.setKudos(true, activityId: id) == KudosState(kudosCount: 4, viewerHasKudoed: true))
        #expect(try await repository.setKudos(false, activityId: id) == KudosState(kudosCount: 3, viewerHasKudoed: false))

        let requests = FeedURLProtocolStub.requests.value
        #expect(requests.map(\.httpMethod) == ["PUT", "DELETE"])
        #expect(requests.allSatisfy { $0.url?.path == "/v1/activities/\(activityId)/kudos" })
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()
        let id = ActivityID(UUID(uuidString: activityId)!)

        FeedURLProtocolStub.handler.value = { _ in (404, Data()) }
        await #expect(throws: FeedError.notFound) { try await repository.setKudos(true, activityId: id) }

        FeedURLProtocolStub.handler.value = { _ in
            (422, Data(#"{"error":{"code":"cannot_kudos_own_activity","message":"x"}}"#.utf8))
        }
        await #expect(throws: FeedError.server(code: "cannot_kudos_own_activity")) {
            try await repository.setKudos(true, activityId: id)
        }

        FeedURLProtocolStub.handler.value = { _ in (401, Data()) }
        await #expect(throws: FeedError.unauthorized) { try await repository.page(cursor: nil) }
    }
}
