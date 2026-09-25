import Foundation
@testable import StravaClone

/// Fake `AuthRepository` (ADR-025 §3): each handler is injectable per test,
/// defaulting to "unexpected call" so a test only has to stub what it exercises.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {
    var signUpHandler: (@Sendable (String, String, String) async throws(AuthError) -> AuthUser)?
    var signInHandler: (@Sendable (String, String) async throws(AuthError) -> AuthUser)?
    var signInWithGoogleHandler: (@Sendable (String) async throws(AuthError) -> AuthUser)?
    var signOutHandler: (@Sendable () async -> Void)?
    var currentUserHandler: (@Sendable () async throws(AuthError) -> AuthUser)?

    func signUp(email: String, password: String, name: String) async throws(AuthError) -> AuthUser {
        guard let signUpHandler else { fatalError("FakeAuthRepository.signUpHandler not set") }
        return try await signUpHandler(email, password, name)
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthUser {
        guard let signInHandler else { fatalError("FakeAuthRepository.signInHandler not set") }
        return try await signInHandler(email, password)
    }

    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser {
        guard let signInWithGoogleHandler else { fatalError("FakeAuthRepository.signInWithGoogleHandler not set") }
        return try await signInWithGoogleHandler(idToken)
    }

    func signOut() async {
        await signOutHandler?()
    }

    func currentUser() async throws(AuthError) -> AuthUser {
        guard let currentUserHandler else { fatalError("FakeAuthRepository.currentUserHandler not set") }
        return try await currentUserHandler()
    }
}
