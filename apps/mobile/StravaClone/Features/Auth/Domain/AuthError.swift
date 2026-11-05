import Foundation

/// Normalized auth error: the Presentation layer only sees these cases (ADR-022, ADR-035 §2).
/// `server(message:)` carries Better Auth's own `message` for cases we don't give a
/// dedicated, translated case to (e.g. an email shape the client-side check missed) — better
/// than silently mislabeling an unrelated error.
enum AuthError: Error, Equatable, Sendable {
    /// No valid session (none in the Keychain, or the server refused it).
    case notSignedIn
    /// Wrong Sign-in code (`INVALID_OTP`); the code stays valid for its remaining attempts.
    case invalidCode
    /// The Sign-in code is past its 5 minutes (`OTP_EXPIRED`): a new one must be requested.
    case codeExpired
    /// The Sign-in code's attempts are used up (`TOO_MANY_ATTEMPTS`): a new one must be requested.
    case tooManyAttempts
    case rateLimited
    /// The account is banned (`403 BANNED_USER`, ADR-038 §6): « Compte suspendu ». Only the
    /// sign-in fails; sending a code to a banned athlete is still accepted.
    case accountSuspended(AccountSuspension)
    case server(message: String)
    case googleSignInCancelled
    case googleSignInFailed(String)
    case appleSignInCancelled
    case appleSignInFailed(String)
    case network(APIError)
}
