import Foundation

/// Coordinates auth state over time: who is signed in, if anyone (ADR-007: services
/// holding shared state are actors). Unlike Recording's single-shot `StartRecording`,
/// sign-up/sign-in/sign-out are transitions of the same shared state, not independent
/// composable operations, so they live directly on this actor rather than as separate
/// use-case structs.
actor AuthService {
    private let repository: any AuthRepository
    private let googleAuthProvider: any GoogleAuthProvider
    private(set) var currentUser: AuthUser?

    init(repository: any AuthRepository, googleAuthProvider: any GoogleAuthProvider) {
        self.repository = repository
        self.googleAuthProvider = googleAuthProvider
    }

    /// Validates whatever session token is already in the Keychain at launch.
    func restoreSession() async -> AuthUser? {
        currentUser = try? await repository.currentUser()
        return currentUser
    }

    func signUp(email: String, password: String, name: String) async throws(AuthError) -> AuthUser {
        let user = try await repository.signUp(email: email, password: password, name: name)
        currentUser = user
        return user
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthUser {
        let user = try await repository.signIn(email: email, password: password)
        currentUser = user
        return user
    }

    func signInWithGoogle() async throws(AuthError) -> AuthUser {
        let idToken = try await googleAuthProvider.signIn()
        let user = try await repository.signInWithGoogle(idToken: idToken)
        currentUser = user
        return user
    }

    func signOut() async {
        await repository.signOut()
        currentUser = nil
    }
}
