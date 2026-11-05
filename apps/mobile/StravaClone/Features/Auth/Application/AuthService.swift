import Foundation

/// Coordinates auth state over time: who is signed in, if anyone (ADR-007: services
/// holding shared state are actors). Unlike Recording's single-shot `StartRecording`,
/// sign-in/sign-out are transitions of the same shared state, not independent
/// composable operations, so they live directly on this actor rather than as separate
/// use-case structs.
actor AuthService {
    private let repository: any AuthRepository
    private let googleAuthProvider: any GoogleAuthProvider
    private let appleAuthProvider: any AppleAuthProvider
    private(set) var currentUser: AuthUser?

    init(repository: any AuthRepository, googleAuthProvider: any GoogleAuthProvider, appleAuthProvider: any AppleAuthProvider = UnavailableAppleAuthProvider()) {
        self.repository = repository
        self.googleAuthProvider = googleAuthProvider
        self.appleAuthProvider = appleAuthProvider
    }

    /// Validates whatever session token is already in the Keychain at launch.
    func restoreSession() async -> AuthUser? {
        currentUser = try? await repository.currentUser()
        return currentUser
    }

    /// Emails a Sign-in code (ADR-035 §2); signing in with it is `signIn(email:code:name:)`.
    func sendSignInCode(email: String) async throws(AuthError) {
        try await repository.sendSignInCode(email: email)
    }

    func signIn(email: String, code: String, name: String?) async throws(AuthError) -> AuthUser {
        let user = try await repository.signIn(email: email, code: code, name: name)
        currentUser = user
        return user
    }

    func signInWithGoogle() async throws(AuthError) -> AuthUser {
        let idToken = try await googleAuthProvider.signIn()
        let user = try await repository.signInWithGoogle(idToken: idToken)
        currentUser = user
        return user
    }

    func signInWithApple() async throws(AuthError) -> AuthUser {
        let idToken = try await appleAuthProvider.signIn()
        let user = try await repository.signInWithApple(idToken: idToken)
        currentUser = user
        return user
    }

    func signOut() async {
        await repository.signOut()
        currentUser = nil
    }
}
