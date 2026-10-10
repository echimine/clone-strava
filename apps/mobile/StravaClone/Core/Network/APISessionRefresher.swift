import Foundation

/// `SessionRefreshing` over Better Auth (ADR-022): `GET /api/auth/get-session` validates the
/// bearer and extends the session; when Better Auth issues a new token it comes back in the
/// `set-auth-token` header and replaces the stored one. No session answers `null`.
struct APISessionRefresher: SessionRefreshing {
    let apiClient: APIClient
    let authSession: AuthSession

    private struct SessionResponse: Decodable {
        struct User: Decodable { let id: String }
        let user: User?
    }

    func refresh() async -> Bool {
        do {
            let (response, http): (SessionResponse?, HTTPURLResponse) = try await apiClient.sendWithHeaders(
                method: "GET",
                path: "/api/auth/get-session",
                body: String?.none
            )
            if let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
                authSession.store(token: token)
            }
            return response?.user != nil
        } catch {
            return false
        }
    }
}
