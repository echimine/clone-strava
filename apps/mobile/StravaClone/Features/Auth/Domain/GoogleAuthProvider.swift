import Foundation

/// Google sign-in port of the Auth domain (ADR-022): GoogleSignIn SDK in the app,
/// a fake provider in tests.
protocol GoogleAuthProvider: Sendable {
    /// Presents the Google sign-in UI and returns the raw Google ID token to send to the backend.
    func signIn() async throws(AuthError) -> String
}
