import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIAthleteRepositoryTests`: suites run in parallel.
private final class FollowURLProtocolStub: URLProtocol, @unchecked Sendable {
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
struct APIFollowRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"

    private func makeRepository() -> APIFollowRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FollowURLProtocolStub.self]
        let authSession = AuthSession(service: "test.follows.\(UUID())")
        authSession.clear()
        FollowURLProtocolStub.requests.value = []
        return APIFollowRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        FollowURLProtocolStub.handler.value = { _ in (status, body) }
    }

    @Test func followingPutsTheFollowAndReturnsThePendingRequest() async throws {
        let repository = makeRepository()
        respond(200, #"{ "athleteId": "\#(athleteId)", "viewerFollowStatus": "pending", "followerCount": 4 }"#)

        let change = try await repository.follow(athleteId)

        let request = try #require(FollowURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/athletes/\(athleteId)/follow")
        #expect(change == FollowChange(athleteId: athleteId, status: .pending, followerCount: 4))
    }

    @Test func unfollowingDeletesTheFollow() async throws {
        let repository = makeRepository()
        respond(200, #"{ "athleteId": "\#(athleteId)", "viewerFollowStatus": "none", "followerCount": 3 }"#)

        let change = try await repository.unfollow(athleteId)

        let request = try #require(FollowURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/athletes/\(athleteId)/follow")
        #expect(change == FollowChange(athleteId: athleteId, status: .none, followerCount: 3))
    }

    @Test func aRefusalKeepsItsCode() async {
        let repository = makeRepository()
        respond(422, #"{ "error": { "code": "cannot_follow_self", "message": "No" } }"#)

        await #expect(throws: AthleteError.server(code: "cannot_follow_self")) {
            try await repository.follow(athleteId)
        }
    }

    @Test func anUnknownAthleteIsNotFound() async {
        let repository = makeRepository()
        respond(404, #"{ "error": { "code": "athlete_not_found", "message": "No" } }"#)

        await #expect(throws: AthleteError.notFound) {
            try await repository.unfollow(athleteId)
        }
    }
}
