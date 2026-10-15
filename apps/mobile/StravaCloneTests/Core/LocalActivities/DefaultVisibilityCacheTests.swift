import Foundation
import Testing
@testable import StravaClone

/// Own stub (suites run in parallel): answers every request from `handler`.
private final class MeURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> ActivityURLProtocolStub.Answer)?>(nil)
    static let paths = Locked<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.paths.value.append(request.url?.path ?? "")
        switch Self.handler.value?(request) ?? .offline {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .status(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .hang:
            break
        }
    }

    override func stopLoading() {}
}

/// The visibility preselected on the finish screen (ADR-031 §11, §13): `GET /v1/me`, cached,
/// `public` if never loaded. Real `APIClient` over a stubbed network, own `UserDefaults` suite.
@Suite(.serialized)
struct DefaultVisibilityCacheTests {
    private let defaults: UserDefaults
    private let cache: DefaultVisibilityCache

    init() {
        let suite = "test.default-visibility.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeURLProtocolStub.self]
        let authSession = AuthSession(service: "test.default-visibility.\(UUID())")
        authSession.clear()
        cache = DefaultVisibilityCache(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            ),
            defaults: defaults
        )
        MeURLProtocolStub.handler.value = nil
        MeURLProtocolStub.paths.value = []
    }

    private func answerMe(defaultVisibility: String) {
        MeURLProtocolStub.handler.value = { _ in
            .status(200, #"{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","email":"a@test.local","name":"A","role":"user","isPremium":false,"defaultVisibility":"\#(defaultVisibility)"}"#)
        }
    }

    @Test func neverLoadedItIsPublic() {
        #expect(cache.cachedDefaultVisibility == .public)
    }

    @Test func theAthletesDefaultIsCachedFromMe() async {
        answerMe(defaultVisibility: "followers")

        await cache.refresh()

        #expect(cache.cachedDefaultVisibility == .followers)
        #expect(MeURLProtocolStub.paths.value == ["/v1/me"])
    }

    @Test func offlineTheLastLoadedValueStays() async {
        answerMe(defaultVisibility: "private")
        await cache.refresh()
        MeURLProtocolStub.handler.value = { _ in .offline }

        await cache.refresh()

        #expect(cache.cachedDefaultVisibility == .private)
    }

    @Test func signOutForgetsIt() async {
        answerMe(defaultVisibility: "private")
        await cache.refresh()

        cache.clear()

        #expect(cache.cachedDefaultVisibility == .public)
    }
}
