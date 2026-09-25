import Foundation

/// Normalized auth error: the Presentation layer only sees these cases (ADR-022).
enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailAlreadyInUse
    case rateLimited
    case googleSignInCancelled
    case googleSignInFailed(String)
    case network(APIError)
}
