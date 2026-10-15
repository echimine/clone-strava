import Foundation
import Testing
@testable import StravaClone

/// Nested in `ActivitySenderTests` to share its serialized network stub.
extension ActivitySenderTests {
    /// The visibility preselected on the finish screen (ADR-031 §11, §13): `GET /v1/me`, cached,
    /// `public` if never loaded. Real `APIClient` over a stubbed network, own `UserDefaults` suite.
    struct DefaultVisibilityCacheTests {
        private let defaults: UserDefaults
        private let cache: DefaultVisibilityCache

        init() {
            let suite = "test.default-visibility.\(UUID())"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ActivityURLProtocolStub.self]
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
            ActivitySenderHarness.resetNetwork()
        }

        private func answerMe(defaultVisibility: String) {
            ActivityURLProtocolStub.handler.value = { _ in
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
            #expect(ActivityURLProtocolStub.requests.value.map { $0.url?.path } == ["/v1/me"])
        }

        @Test func offlineTheLastLoadedValueStays() async {
            answerMe(defaultVisibility: "private")
            await cache.refresh()
            ActivityURLProtocolStub.handler.value = { _ in .offline }

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
}
