import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub (suites run in parallel), with response headers.
private final class SessionURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, [String: String], Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let (status, headers, body) = Self.handler.value?(request) ?? (500, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Session refresh after a `401` (ADR-008 §5) over Better Auth's `get-session` (ADR-022).
@Suite(.serialized)
struct APISessionRefresherTests {
    private func make() -> (APISessionRefresher, AuthSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionURLProtocolStub.self]
        let authSession = AuthSession(service: "test.session-refresher.\(UUID())")
        authSession.clear()
        authSession.store(token: "old-token")
        SessionURLProtocolStub.requests.value = []
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: configuration),
            authSession: authSession
        )
        return (APISessionRefresher(apiClient: apiClient, authSession: authSession), authSession)
    }

    @Test func aValidSessionIsRefreshedAndItsNewTokenKept() async throws {
        let (refresher, authSession) = make()
        defer { authSession.clear() }
        SessionURLProtocolStub.handler.value = { _ in
            (200, ["set-auth-token": "new-token"], Data(#"{"session":{"id":"s"},"user":{"id":"u","email":"a@b.c","name":"A"}}"#.utf8))
        }

        #expect(await refresher.refresh())

        let request = try #require(SessionURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/auth/get-session")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token")
        #expect(authSession.token() == "new-token")
    }

    @Test func aSessionStillValidKeepsItsToken() async {
        let (refresher, authSession) = make()
        defer { authSession.clear() }
        SessionURLProtocolStub.handler.value = { _ in (200, [:], Data(#"{"user":{"id":"u"}}"#.utf8)) }

        #expect(await refresher.refresh())
        #expect(authSession.token() == "old-token")
    }

    @Test func anExpiredSessionCannotBeRefreshed() async {
        let (refresher, authSession) = make()
        defer { authSession.clear() }

        SessionURLProtocolStub.handler.value = { _ in (200, [:], Data("null".utf8)) }
        #expect(await refresher.refresh() == false)

        SessionURLProtocolStub.handler.value = { _ in (401, [:], Data()) }
        #expect(await refresher.refresh() == false)
    }
}
