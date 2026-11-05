import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class AthleteURLProtocolStub: URLProtocol, @unchecked Sendable {
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
struct APIAthleteRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"

    private func makeRepository() -> APIAthleteRepository {
        APIAthleteRepository(apiClient: makeAPIClient())
    }

    private func makeAPIClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AthleteURLProtocolStub.self]
        let authSession = AuthSession(service: "test.athletes.\(UUID())")
        authSession.clear()
        AthleteURLProtocolStub.requests.value = []
        return APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: configuration),
            authSession: authSession
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        AthleteURLProtocolStub.handler.value = { _ in (status, body) }
    }

    private func lastRequestComponents() throws -> URLComponents {
        let request = try #require(AthleteURLProtocolStub.requests.value.last)
        return try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    }

    @Test func decodesMyOwnProfileWithItsNullFollowStatus() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "athlete": { "id": "\(athleteId)", "displayName": "Camille Martin", "avatarUrl": null },
          "activityCount": 42, "streakWeeks": 5, "followerCount": 12, "followingCount": 8,
          "viewerFollowStatus": null,
          "followersYouKnow": [],
          "practicedSports": ["run", "ride"],
          "approveFollowers": true, "pendingFollowRequestCount": 2, "itineraryCount": 3
        }
        """)

        let profile = try await repository.profile(of: athleteId)

        #expect(try lastRequestComponents().path == "/v1/athletes/\(athleteId)")
        #expect(profile == AthleteProfile(
            athlete: ActivityAuthor(id: athleteId, displayName: "Camille Martin", avatarURL: nil),
            activityCount: 42,
            streakWeeks: 5,
            followerCount: 12,
            followingCount: 8,
            viewerFollowStatus: nil,
            followersYouKnow: [],
            practicedSports: [.run, .ride],
            approveFollowers: true,
            pendingFollowRequestCount: 2,
            itineraryCount: 3
        ))
    }

    @Test func decodesAnotherAthletesProfileWithoutTheOwnOnlyFields() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "athlete": { "id": "\(athleteId)", "displayName": "Léa Bernard", "avatarUrl": "https://cdn.test/l.png" },
          "activityCount": 3, "streakWeeks": 0, "followerCount": 1, "followingCount": 0,
          "viewerFollowStatus": "pending",
          "followersYouKnow": [{ "id": "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f02", "displayName": "Hugo Petit", "avatarUrl": null }],
          "practicedSports": []
        }
        """)

        let profile = try await repository.profile(of: athleteId)

        #expect(profile.viewerFollowStatus == .pending)
        #expect(profile.athlete.avatarURL == URL(string: "https://cdn.test/l.png"))
        #expect(profile.followersYouKnow.map(\.displayName) == ["Hugo Petit"])
        #expect(profile.approveFollowers == nil)
        #expect(profile.itineraryCount == nil)
    }

    @Test func anUnknownAthleteIsNotFound() async {
        let repository = makeRepository()
        respond(404, #"{ "error": { "code": "athlete_not_found" } }"#)

        await #expect(throws: AthleteError.notFound) {
            _ = try await repository.profile(of: athleteId)
        }
    }

    @Test func listsTheAthletesActivitiesAsFeedCards() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "items": [{
            "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
            "title": "Sortie du matin",
            "sportTypeCode": "run",
            "startedAt": "2026-10-02T12:32:00.123Z",
            "visibility": "public",
            "locationName": null,
            "stats": { "distanceM": 10000, "movingTimeS": 3000, "elapsedTimeS": 3100, "elevationGainM": 50, "avgSpeedMs": 3.3 },
            "map": null,
            "routeTrimmed": false,
            "author": { "id": "\(athleteId)", "displayName": "Camille Martin", "avatarUrl": null },
            "engagement": { "kudosCount": 2, "commentCount": 0, "viewerHasKudoed": false },
            "recentKudos": [],
            "viewerIsAuthor": true,
            "media": [],
            "mediaFirst": false,
            "medalCounts": { "gold": 0, "silver": 0, "bronze": 0 }
          }],
          "nextCursor": "next"
        }
        """)

        let page = try await repository.activities(of: athleteId, cursor: "prev")

        let components = try lastRequestComponents()
        #expect(components.path == "/v1/athletes/\(athleteId)/activities")
        #expect(components.queryItems == [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "cursor", value: "prev")])
        #expect(page.nextCursor == "next")
        #expect(page.posts.map(\.title) == ["Sortie du matin"])
        #expect(page.posts.first?.distance == Distance(meters: 10_000))
        #expect(page.posts.first?.viewerIsAuthor == true)
    }

    @Test func listsTheAthletesGalleryWithEachMediasActivity() async throws {
        let repository = APIAthleteGalleryRepository(apiClient: makeAPIClient())
        let mediaId = "3f2b8e1a-6c4d-4e9f-8a7b-1c2d3e4f5a6b"
        respond(200, """
        {
          "items": [{
            "id": "\(mediaId)",
            "kind": "video",
            "width": 1080,
            "height": 1920,
            "durationMs": 10000,
            "url": "https://bucket.test/m/original.mp4?X-Amz-Expires=3600",
            "posterUrl": "https://bucket.test/m/poster.jpg?X-Amz-Expires=3600",
            "thumbUrl": "https://bucket.test/m/thumb.jpg?X-Amz-Expires=3600",
            "activity": { "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "title": "Sortie du matin", "startedAt": "2026-10-02T12:32:00.000Z" }
          }],
          "nextCursor": "next"
        }
        """)

        let page = try await repository.gallery(of: athleteId, cursor: "prev")

        let components = try lastRequestComponents()
        #expect(components.path == "/v1/athletes/\(athleteId)/media")
        #expect(components.queryItems == [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "cursor", value: "prev")])
        #expect(page.nextCursor == "next")
        let item = try #require(page.items.first)
        #expect(item.media.id == UUID(uuidString: mediaId))
        #expect(item.media.kind == .video)
        #expect(item.media.duration == .seconds(10))
        #expect(item.media.thumbURL.lastPathComponent == "thumb.jpg")
        #expect(item.activity.id.description == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        #expect(item.activity.title == "Sortie du matin")
        #expect(item.activity.startedAt == Date(timeIntervalSince1970: 1_790_944_320))
    }
}
