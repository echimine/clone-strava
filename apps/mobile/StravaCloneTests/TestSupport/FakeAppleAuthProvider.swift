import Foundation
@testable import StravaClone

final class FakeAppleAuthProvider: AppleAuthProvider, @unchecked Sendable {
    var result: Result<String, AuthError> = .success("apple-token")
    func signIn() async throws(AuthError) -> String { try result.get() }
}
