import Foundation

protocol AppleAuthProvider: Sendable {
    func signIn() async throws(AuthError) -> String
}

struct UnavailableAppleAuthProvider: AppleAuthProvider {
    func signIn() async throws(AuthError) -> String { throw .appleSignInFailed("Apple Sign-In indisponible") }
}
