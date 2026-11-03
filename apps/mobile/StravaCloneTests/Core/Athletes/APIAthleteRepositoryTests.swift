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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AthleteURLProtocolStub.self]
        let authSession = AuthSession(service: "test.athletes.\(UUID())")
        authSession.clear()
        AthleteURLProtocolStub.requests.value = []
        return APIAthleteRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
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
            "viewerIsAuthor": true
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

    @Test func yearToDateDistanceIsAllSports() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "recent": { "weeks": 4, "activitiesPerWeek": 1.5, "movingTimeSPerWeek": 3600, "distanceMPerWeek": 12000 },
          "yearToDate": { "activityCount": 40, "movingTimeS": 90000, "distanceM": 412345.6, "elevationGainM": 3000 },
          "allTime": { "activityCount": 80, "distanceM": 900000, "elevationGainM": 7000 }
        }
        """)

        let distance = try await repository.yearToDateDistance(of: athleteId)

        let components = try lastRequestComponents()
        #expect(components.path == "/v1/athletes/\(athleteId)/stats")
        #expect(components.queryItems == nil)
        #expect(distance == Distance(meters: 412_345.6))
    }
}
