import Foundation

/// `APIClient` adapter of `AuthRepository` (ADR-022, ADR-035 §2): talks to Better Auth's native
/// endpoints under `/api/auth/*` (outside the `/v1` prefix), stores the bearer token
/// Better Auth returns in the `set-auth-token` response header.
struct APIAuthRepository: AuthRepository {
    let apiClient: APIClient
    let authSession: AuthSession

    private struct SendSignInCodeBody: Encodable {
        let email: String
        /// emailOTP has no separate sign-up type: a "sign-in" code also creates the account.
        let type = "sign-in"
    }

    private struct SignInCodeBody: Encodable {
        let email: String
        let otp: String
        /// Left out of the JSON when `nil` (synthesized `encodeIfPresent`).
        let name: String?
    }

    private struct SignInSocialBody: Encodable {
        let provider = "google"
        let idToken: IdTokenBody
        struct IdTokenBody: Encodable { let token: String }
    }

    private struct UserResponse: Decodable {
        let user: RemoteUser
    }

    private struct RemoteUser: Decodable {
        let id: String
        let email: String
        let name: String
        let createdAt: Date?
    }

    func sendSignInCode(email: String) async throws(AuthError) {
        do {
            let _: NoContent = try await apiClient.send(
                method: "POST",
                path: "/api/auth/email-otp/send-verification-otp",
                body: SendSignInCodeBody(email: email)
            )
        } catch {
            throw mapError(error)
        }
    }

    func signIn(email: String, code: String, name: String?) async throws(AuthError) -> AuthUser {
        do {
            return try await performAuthRequest(
                path: "/api/auth/sign-in/email-otp",
                body: SignInCodeBody(email: email, otp: code, name: name)
            )
        } catch {
            // `performAuthRequest` only ever throws `AuthError` (see its doc comment).
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
        _ = try? await apiClient.send(method: "POST", path: "/api/auth/sign-out", body: Optional<String>.none) as NoContent
    }

    func currentUser() async throws(AuthError) -> AuthUser {
        let result: Result<AuthUser, AuthError>
        do {
            let endpoint = SessionEndpoint(apiClient: apiClient, authSession: authSession)
            if let user = try await endpoint.user(as: RemoteUser.self) {
                result = .success(AuthUser(id: user.id, email: user.email, name: user.name))
            } else {
                result = .failure(.notSignedIn)
            }
        } catch {
            result = .failure(mapError(error))
        }
        return try result.get()
    }

    // Untyped `throws`, not `throws(AuthError)`: Swift 6.4's typed-throws SILGen crashes
    // on a generic function (here, `Body: Encodable`) that maps a caught error to a
    // different typed-throws error. Callers (signIn/signInWithGoogle, both non-generic)
    // re-throw as `AuthError` themselves, where typed throws is safe.
    private func performAuthRequest<Body: Encodable>(path: String, body: Body) async throws -> AuthUser {
        do {
            let (response, http): (UserResponse, HTTPURLResponse) =
                try await apiClient.sendWithHeaders(method: "POST", path: path, body: body)
            if let token = http.value(forHTTPHeaderField: "set-auth-token") {
                authSession.store(token: token)
            }
            let user = response.user
            return AuthUser(id: user.id, email: user.email, name: user.name, createdAt: user.createdAt)
        } catch {
            throw mapError(error)
        }
    }

    /// Better Auth's error body shape: `{ code, message }` (better-call's `APIError`).
    private struct ServerErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    private func mapError(_ error: APIError) -> AuthError {
        switch error {
        case .unauthorized:
            return .notSignedIn
        case let .http(status: 429, body: _):
            return .rateLimited
        case let .http(status: _, body: body):
            let server = body.flatMap { try? JSONDecoder().decode(ServerErrorBody.self, from: $0) }
            switch server?.code {
            case "INVALID_OTP":
                return .invalidCode
            case "OTP_EXPIRED":
                return .codeExpired
            case "TOO_MANY_ATTEMPTS":
                return .tooManyAttempts
            default:
                // Any other server-side rejection: surface the server's own message rather
                // than guessing — see AuthError.server's doc comment.
                return .server(message: server?.message ?? "Une erreur est survenue (code \(errorStatus(error)))")
            }
        default:
            return .network(error)
        }
    }

    private func errorStatus(_ error: APIError) -> Int {
        if case .http(let status, _) = error { return status }
        return -1
    }
}
