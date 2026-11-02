import Foundation
import Testing
@testable import StravaClone

/// The app authenticates with a bearer token only (ADR-022). A `Cookie` header left over from
/// an earlier response makes Better Auth demand an `Origin` the app never sends
/// (`403 MISSING_OR_NULL_ORIGIN` on `/api/auth/*`), so the API session never handles cookies.
struct APIClientCookieTests {
    @Test func theDefaultAPISessionNeitherSendsNorStoresCookies() {
        let configuration = APIClient.defaultSession.configuration

        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpCookieStorage == nil)
    }

    @Test func anAPIClientBuiltWithoutASessionUsesTheCookielessSession() {
        let client = APIClient(baseURL: URL(string: "https://api.test")!, authSession: AuthSession(service: "test.api-cookies.\(UUID())"))

        #expect(client.session === APIClient.defaultSession)
    }
}
