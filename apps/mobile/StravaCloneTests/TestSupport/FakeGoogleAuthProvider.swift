import Foundation
@testable import StravaClone

/// Fake `GoogleAuthProvider` (ADR-025 §3): returns a fixed token or throws, per test.
final class FakeGoogleAuthProvider: GoogleAuthProvider, @unchecked Sendable {
    var signInHandler: (@Sendable () async throws(AuthError) -> String)?

    func signIn() async throws(AuthError) -> String {
        guard let signInHandler else { fatalError("FakeGoogleAuthProvider.signInHandler not set") }
        return try await signInHandler()
    }
}
