import Foundation
@testable import StravaClone

/// Fake `AuthRepository` (ADR-025 §3): each handler is injectable per test,
/// defaulting to "unexpected call" so a test only has to stub what it exercises.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {
    var sendSignInCodeHandler: (@Sendable (String) async throws(AuthError) -> Void)?
    var signInHandler: (@Sendable (String, String, String?) async throws(AuthError) -> AuthUser)?
    var signInWithGoogleHandler: (@Sendable (String) async throws(AuthError) -> AuthUser)?
    var signInWithAppleHandler: (@Sendable (String) async throws(AuthError) -> AuthUser)?
    var signOutHandler: (@Sendable () async -> Void)?
    var currentUserHandler: (@Sendable () async throws(AuthError) -> AuthUser)?

    func sendSignInCode(email: String) async throws(AuthError) {
        guard let sendSignInCodeHandler else { fatalError("FakeAuthRepository.sendSignInCodeHandler not set") }
        try await sendSignInCodeHandler(email)
    }

    func signIn(email: String, code: String, name: String?) async throws(AuthError) -> AuthUser {
        guard let signInHandler else { fatalError("FakeAuthRepository.signInHandler not set") }
        return try await signInHandler(email, code, name)
    }

    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser {
        guard let signInWithGoogleHandler else { fatalError("FakeAuthRepository.signInWithGoogleHandler not set") }
        return try await signInWithGoogleHandler(idToken)
    }

    func signInWithApple(idToken: String) async throws(AuthError) -> AuthUser {
        guard let signInWithAppleHandler else { fatalError("FakeAuthRepository.signInWithAppleHandler not set") }
        return try await signInWithAppleHandler(idToken)
    }

    func signOut() async {
        await signOutHandler?()
    }

    func currentUser() async throws(AuthError) -> AuthUser {
        guard let currentUserHandler else { fatalError("FakeAuthRepository.currentUserHandler not set") }
        return try await currentUserHandler()
    }
}
