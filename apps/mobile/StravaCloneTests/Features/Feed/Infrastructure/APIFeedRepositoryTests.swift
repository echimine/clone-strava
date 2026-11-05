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
            "stats": { "distanceM": 42195.5, "movingTimeS": 5400, "elapsedTimeS": 5600, "elevationGainM": null, "avgSpeedMs": 7.8 },
            "map": { "polyline": "_p~iF~ps|U_ulLnnqC", "precision": 5 },
            "routeTrimmed": true,
            "author": { "id": "u1", "displayName": "Camille Martin", "avatarUrl": "https://cdn.test/a.png" },
            "engagement": { "kudosCount": 3, "commentCount": 1, "viewerHasKudoed": true },
            "recentKudos": [
              { "id": "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01", "displayName": "Léa Bernard", "avatarUrl": "https://cdn.test/l.png" },
              { "id": "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f02", "displayName": "Hugo Petit", "avatarUrl": null }
            ],
            "viewerIsAuthor": false,
            "media": [
              { "id": "3f1c2a4e-8b6d-4e2f-9a1b-5c7d8e9f0a11", "kind": "video", "width": 1280, "height": 720, "durationMs": 10500,
                "url": "https://bucket.test/m1/original.mp4?X-Amz-Signature=a", "posterUrl": "https://bucket.test/m1/poster.jpg?X-Amz-Signature=b",
                "thumbUrl": "https://bucket.test/m1/thumb.jpg?X-Amz-Signature=c" },
              { "id": "3f1c2a4e-8b6d-4e2f-9a1b-5c7d8e9f0a12", "kind": "photo", "width": 2048, "height": 1536, "durationMs": null,
                "url": "https://bucket.test/m2/original.jpg?X-Amz-Signature=d", "posterUrl": null,
                "thumbUrl": "https://bucket.test/m2/thumb.jpg?X-Amz-Signature=e" }
            ],
            "mediaFirst": true,
            "medalCounts": { "gold": 2, "silver": 0, "bronze": 1 }
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

    @Test func decodesTheCardFieldsOfADR036() async throws {
        let repository = makeRepository()
        let json = feedJSON
        FeedURLProtocolStub.handler.value = { _ in (200, json) }

        let post = try #require(try await repository.page(cursor: nil).posts.first)

        #expect(post.avgSpeedMs == 7.8)
        #expect(post.routeTrimmed)
        #expect(post.recentKudos == [
            ActivityAuthor(id: "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01", displayName: "Léa Bernard", avatarURL: URL(string: "https://cdn.test/l.png")),
            ActivityAuthor(id: "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f02", displayName: "Hugo Petit", avatarURL: nil),
        ])
    }

    /// ADR-037 §7: the card's Media in order, with their signed URLs, and "media first".
    @Test func decodesTheMediaOfACard() async throws {
        let repository = makeRepository()
        let json = feedJSON
        FeedURLProtocolStub.handler.value = { _ in (200, json) }

        let post = try #require(try await repository.page(cursor: nil).posts.first)

        #expect(post.mediaFirst)
        #expect(post.medalCounts == MedalCounts(gold: 2, silver: 0, bronze: 1))
        #expect(post.media == [
            ActivityMedia(
                id: UUID(uuidString: "3f1c2a4e-8b6d-4e2f-9a1b-5c7d8e9f0a11")!,
                kind: .video,
                width: 1_280,
                height: 720,
                duration: .milliseconds(10_500),
                url: URL(string: "https://bucket.test/m1/original.mp4?X-Amz-Signature=a")!,
                posterURL: URL(string: "https://bucket.test/m1/poster.jpg?X-Amz-Signature=b"),
                thumbURL: URL(string: "https://bucket.test/m1/thumb.jpg?X-Amz-Signature=c")!
            ),
            ActivityMedia(
                id: UUID(uuidString: "3f1c2a4e-8b6d-4e2f-9a1b-5c7d8e9f0a12")!,
                kind: .photo,
                width: 2_048,
                height: 1_536,
                duration: nil,
                url: URL(string: "https://bucket.test/m2/original.jpg?X-Amz-Signature=d")!,
                posterURL: nil,
                thumbURL: URL(string: "https://bucket.test/m2/thumb.jpg?X-Amz-Signature=e")!
            ),
        ])
    }

    @Test func loadsTheThreeMostRecentKudosGivers() async throws {
        let repository = makeRepository()
        FeedURLProtocolStub.handler.value = { _ in
            (200, Data("""
            {
              "items": [
                { "athlete": { "id": "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01", "displayName": "Léa Bernard", "avatarUrl": null },
                  "givenAt": "2026-10-02T12:32:00.123Z" }
              ],
              "nextCursor": null
            }
            """.utf8))
        }
        let id = ActivityID(UUID(uuidString: activityId)!)

        let givers = try await repository.recentKudos(activityId: id)

        #expect(givers == [ActivityAuthor(id: "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01", displayName: "Léa Bernard", avatarURL: nil)])
        let request = try #require(FeedURLProtocolStub.requests.value.first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/activities/\(activityId)/kudos")
        #expect(components.queryItems == [URLQueryItem(name: "limit", value: "3")])
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
