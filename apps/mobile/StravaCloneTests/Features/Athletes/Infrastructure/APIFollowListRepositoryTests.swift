import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFollowRepositoryTests`: suites run in parallel.
private final class FollowListURLProtocolStub: URLProtocol, @unchecked Sendable {
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
struct APIFollowListRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"
    private let otherId = "5d3c2b1a-0f9e-4d8c-8b7a-6e5d4c3b2a10"

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FollowListURLProtocolStub.self]
        let authSession = AuthSession(service: "test.follow-lists.\(UUID())")
        authSession.clear()
        FollowListURLProtocolStub.requests.value = []
        return APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: configuration),
            authSession: authSession
        )
    }

    private func respond(_ status: Int, _ json: String = "") {
        let body = Data(json.utf8)
        FollowListURLProtocolStub.handler.value = { _ in (status, body) }
    }

    private var lastRequest: URLRequest? { FollowListURLProtocolStub.requests.value.last }

    private func query(_ name: String) -> String? {
        lastRequest.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    @Test func readsAPageOfFollowersWithTheViewersOwnRowWithoutAButton() async throws {
        let repository = APIFollowListRepository(apiClient: makeClient())
        respond(200, """
        { "items": [
            { "athlete": { "id": "\(athleteId)", "displayName": "Léa Bernard", "avatarUrl": "https://img.test/lea.jpg" }, "viewerFollowStatus": "accepted" },
            { "athlete": { "id": "\(otherId)", "displayName": "Moi", "avatarUrl": null }, "viewerFollowStatus": null }
          ], "nextCursor": "c2" }
        """)

        let page = try await repository.list(.followers, of: athleteId, cursor: "c1")

        #expect(lastRequest?.httpMethod == "GET")
        #expect(lastRequest?.url?.path == "/v1/athletes/\(athleteId)/followers")
        #expect(query("cursor") == "c1")
        #expect(query("limit") == "20")
        #expect(page == AthleteListPage(
            items: [
                AthleteListItem(
                    athlete: ActivityAuthor(id: athleteId, displayName: "Léa Bernard", avatarURL: URL(string: "https://img.test/lea.jpg")),
                    viewerFollowStatus: .accepted
                ),
                AthleteListItem(athlete: ActivityAuthor(id: otherId, displayName: "Moi", avatarURL: nil), viewerFollowStatus: nil),
            ],
            nextCursor: "c2"
        ))
    }

    @Test func readsTheFollowingListFromItsFirstPage() async throws {
        let repository = APIFollowListRepository(apiClient: makeClient())
        respond(200, #"{ "items": [], "nextCursor": null }"#)

        let page = try await repository.list(.following, of: athleteId, cursor: nil)

        #expect(lastRequest?.url?.path == "/v1/athletes/\(athleteId)/following")
        #expect(query("cursor") == nil)
        #expect(page == AthleteListPage(items: [], nextCursor: nil))
    }

    @Test func readsTheFollowRequests() async throws {
        let repository = APIFollowListRepository(apiClient: makeClient())
        respond(200, """
        { "items": [
            { "athlete": { "id": "\(athleteId)", "displayName": "Léa Bernard", "avatarUrl": null }, "viewerFollowStatus": "none", "requestedAt": "2026-11-02T08:30:00.000Z" }
          ], "nextCursor": null }
        """)

        let page = try await repository.followRequests(cursor: nil)

        #expect(lastRequest?.url?.path == "/v1/me/follow-requests")
        #expect(page.items == [
            FollowRequest(
                athlete: ActivityAuthor(id: athleteId, displayName: "Léa Bernard", avatarURL: nil),
                viewerFollowStatus: FollowStatus.none,
                requestedAt: Date(timeIntervalSince1970: 1_793_608_200)
            ),
        ])
    }

    @Test func acceptsRefusesAndRemoves() async throws {
        let repository = APIFollowListRepository(apiClient: makeClient())
        respond(204)

        try await repository.acceptRequest(from: athleteId)
        #expect(lastRequest?.httpMethod == "PUT")
        #expect(lastRequest?.url?.path == "/v1/me/follow-requests/\(athleteId)")

        try await repository.refuseRequest(from: athleteId)
        #expect(lastRequest?.httpMethod == "DELETE")
        #expect(lastRequest?.url?.path == "/v1/me/follow-requests/\(athleteId)")

        try await repository.removeFollower(athleteId)
        #expect(lastRequest?.httpMethod == "DELETE")
        #expect(lastRequest?.url?.path == "/v1/me/followers/\(athleteId)")
    }

    @Test func aRequestAlreadyGoneIsNotFound() async {
        let repository = APIFollowListRepository(apiClient: makeClient())
        respond(404, #"{ "error": { "code": "follow_request_not_found", "message": "No" } }"#)

        await #expect(throws: AthleteError.notFound) {
            try await repository.acceptRequest(from: athleteId)
        }
    }

    @Test func searchesByName() async throws {
        let repository = APIAthleteSearchRepository(apiClient: makeClient())
        respond(200, """
        { "items": [
            { "athlete": { "id": "\(athleteId)", "displayName": "Éliott Martin", "avatarUrl": null }, "viewerFollowStatus": "pending" }
          ] }
        """)

        let items = try await repository.search("Éli")

        #expect(lastRequest?.url?.path == "/v1/athletes/search")
        #expect(query("q") == "Éli")
        #expect(items == [
            AthleteListItem(athlete: ActivityAuthor(id: athleteId, displayName: "Éliott Martin", avatarURL: nil), viewerFollowStatus: .pending),
        ])
    }
}
