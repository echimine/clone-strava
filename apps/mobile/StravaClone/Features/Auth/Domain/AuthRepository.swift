import Foundation

/// Auth backend port (ADR-022): email/password and Google sign-in, backed by a
/// single Better Auth instance on the server, bearer token on the mobile side.
protocol AuthRepository: Sendable {
    func signUp(email: String, password: String, name: String) async throws(AuthError) -> AuthUser
    func signIn(email: String, password: String) async throws(AuthError) -> AuthUser
    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser
    func signOut() async
    /// Validates whatever token is already in the Keychain, rather than trusting its mere presence.
    func currentUser() async throws(AuthError) -> AuthUser
}
