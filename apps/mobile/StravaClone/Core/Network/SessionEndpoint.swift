import Foundation

/// Better Auth's `GET /api/auth/get-session` (ADR-022), shared by the launch-time session
/// check (`APIAuthRepository`) and the refresh after a `401` (`APISessionRefresher`): it
/// validates the bearer and extends the session; when Better Auth issues a new token, it
/// comes back in the `set-auth-token` header and replaces the stored one.
struct SessionEndpoint: Sendable {
    let apiClient: APIClient
    let authSession: AuthSession

    private struct Response<User: Decodable>: Decodable {
        let user: User?
    }

    /// The session's user, decoded as `User`; `nil` when there is no session (Better Auth
    /// answers `null`).
    func user<User: Decodable>(as _: User.Type) async throws(APIError) -> User? {
        let (response, http): (Response<User>?, HTTPURLResponse) = try await apiClient.sendWithHeaders(
            method: "GET",
            path: "/api/auth/get-session",
            body: String?.none
        )
        if let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
            authSession.store(token: token)
        }
        return response?.user
    }
}
