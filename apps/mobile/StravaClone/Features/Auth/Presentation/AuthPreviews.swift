#if DEBUG
import Foundation

/// An `AuthStore` for the account screens' previews: every code is sent, "000000" signs in,
/// any other code is wrong.
extension AuthStore {
    static var preview: AuthStore {
        AuthStore(service: AuthService(repository: PreviewAuthRepository(), googleAuthProvider: PreviewGoogle()))
    }
}

private struct PreviewAuthRepository: AuthRepository {
    private static let user = AuthUser(id: "preview", email: "camille.martin@gmail.com", name: "Camille Martin")

    func sendSignInCode(email: String) async throws(AuthError) {}

    func signIn(email: String, code: String, name: String?) async throws(AuthError) -> AuthUser {
        guard code == "000000" else { throw .invalidCode }
        return Self.user
    }

    func signInWithGoogle(idToken: String) async throws(AuthError) -> AuthUser { Self.user }
    func signOut() async {}
    func currentUser() async throws(AuthError) -> AuthUser { throw .notSignedIn }
}

private struct PreviewGoogle: GoogleAuthProvider {
    func signIn() async throws(AuthError) -> String { throw .googleSignInCancelled }
}
#endif
