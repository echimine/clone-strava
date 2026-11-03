import Foundation

/// Auth backend port (ADR-022, ADR-035 §2): Sign-in code by email and Google sign-in, backed
/// by a single Better Auth instance on the server, bearer token on the mobile side. There is no
/// password in the app.
protocol AuthRepository: Sendable {
    /// Emails a 6-digit Sign-in code to `email`, whether or not an account exists yet.
    func sendSignInCode(email: String) async throws(AuthError)
    /// Signs in with the code just sent. The first valid code creates the account, named `name`
    /// when one is given (ignored for an existing account).
    func signIn(email: String, code: String, name: String?) async throws(AuthError) -> AuthUser
    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser
    func signInWithApple(idToken: String) async throws(AuthError) -> AuthUser
    func signOut() async
    /// Validates whatever token is already in the Keychain, rather than trusting its mere presence.
    func currentUser() async throws(AuthError) -> AuthUser
}
