import Foundation

/// Normalized auth error: the Presentation layer only sees these cases (ADR-022).
/// `server(message:)` carries Better Auth's own `message` for cases we don't give a
/// dedicated, translated case to (e.g. password too short/long) — better than silently
/// mislabeling an unrelated error as "invalid credentials" or "email already in use".
enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailAlreadyInUse
    case rateLimited
    case server(message: String)
    case googleSignInCancelled
    case googleSignInFailed(String)
    case network(APIError)
}
