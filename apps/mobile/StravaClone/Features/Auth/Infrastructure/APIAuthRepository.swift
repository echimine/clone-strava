import Foundation

/// `APIClient` adapter of `AuthRepository` (ADR-022): talks to Better Auth's native
/// endpoints under `/api/auth/*` (outside the `/v1` prefix), stores the bearer token
/// Better Auth returns in the `set-auth-token` response header.
struct APIAuthRepository: AuthRepository {
    let apiClient: APIClient
    let authSession: AuthSession

    private struct SignUpBody: Encodable {
        let email: String
        let password: String
        let name: String
    }

    private struct SignInBody: Encodable {
        let email: String
        let password: String
    }

    private struct SignInSocialBody: Encodable {
        let provider = "google"
        let idToken: IdTokenBody
        struct IdTokenBody: Encodable { let token: String }
    }

    private struct UserResponse: Decodable {
        let user: RemoteUser
    }

    private struct SessionResponse: Decodable {
        let user: RemoteUser?
    }

    private struct RemoteUser: Decodable {
        let id: String
        let email: String
        let name: String
    }

    func signUp(email: String, password: String, name: String) async throws(AuthError) -> AuthUser {
        do {
            return try await performAuthRequest(
                path: "/api/auth/sign-up/email",
                body: SignUpBody(email: email, password: password, name: name)
            )
        } catch {
            // `performAuthRequest` only ever throws `AuthError` (see its doc comment).
            throw error as! AuthError
        }
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthUser {
        do {
            return try await performAuthRequest(
                path: "/api/auth/sign-in/email",
                body: SignInBody(email: email, password: password)
            )
        } catch {
            throw error as! AuthError
        }
    }

    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser {
        do {
            return try await performAuthRequest(
                path: "/api/auth/sign-in/social",
                body: SignInSocialBody(idToken: .init(token: idToken))
            )
        } catch {
            throw error as! AuthError
        }
    }

    func signOut() async {
        authSession.clear()
        // Best-effort: let the server revoke the session too (ADR-022 "revokeSession").
        // Failure here must not block a local sign-out, so it is intentionally not awaited-and-thrown.
        _ = try? await apiClient.send(method: "POST", path: "/api/auth/sign-out", body: Optional<String>.none) as EmptyResponse
    }

    private struct EmptyResponse: Decodable {}

    func currentUser() async throws(AuthError) -> AuthUser {
        let result: Result<AuthUser, AuthError>
        do {
            let response: SessionResponse = try await apiClient.get("/api/auth/get-session")
            if let user = response.user {
                result = .success(AuthUser(id: user.id, email: user.email, name: user.name))
            } else {
                result = .failure(.invalidCredentials)
            }
        } catch {
            result = .failure(mapError(error))
        }
        return try result.get()
    }

    // Untyped `throws`, not `throws(AuthError)`: Swift 6.4's typed-throws SILGen crashes
    // on a generic function (here, `Body: Encodable`) that maps a caught error to a
    // different typed-throws error. Callers (signUp/signIn/signInWithGoogle, all
    // non-generic) re-throw as `AuthError` themselves, where typed throws is safe.
    private func performAuthRequest<Body: Encodable>(path: String, body: Body) async throws -> AuthUser {
        do {
            let (response, http): (UserResponse, HTTPURLResponse) =
                try await apiClient.sendWithHeaders(method: "POST", path: path, body: body)
            if let token = http.value(forHTTPHeaderField: "set-auth-token") {
                authSession.store(token: token)
            }
            return AuthUser(id: response.user.id, email: response.user.email, name: response.user.name)
        } catch {
            throw mapError(error)
        }
    }

    private func mapError(_ error: APIError) -> AuthError {
        switch error {
        case .http(status: 429):
            return .rateLimited
        case .http(status: 400), .http(status: 422):
            // Sign-up with an email already in use (exact status/shape not covered by
            // backend tests yet — ADR-022/§10 risk, to confirm against the real API).
            return .emailAlreadyInUse
        case .unauthorized:
            return .invalidCredentials
        default:
            return .network(error)
        }
    }
}
