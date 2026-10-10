import Foundation

/// `SessionRefreshing` over Better Auth (ADR-022): `get-session` (`SessionEndpoint`)
/// validates the bearer and extends the session, keeping any new token. No session, or any
/// failure, means the athlete must sign in again.
struct APISessionRefresher: SessionRefreshing {
    let apiClient: APIClient
    let authSession: AuthSession

    private struct User: Decodable {
        let id: String
    }

    func refresh() async -> Bool {
        let endpoint = SessionEndpoint(apiClient: apiClient, authSession: authSession)
        return (try? await endpoint.user(as: User.self)) != nil
    }
}
