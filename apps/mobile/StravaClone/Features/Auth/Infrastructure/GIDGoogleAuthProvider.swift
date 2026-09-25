import Foundation
import GoogleSignIn
import UIKit

/// GoogleSignIn-iOS adapter of `GoogleAuthProvider` (ADR-022). `GIDClientID` is read
/// from Info.plist by the SDK at launch (Config/Base.xcconfig, project.yml).
@MainActor
final class GIDGoogleAuthProvider: GoogleAuthProvider {
    func signIn() async throws(AuthError) -> String {
        guard let rootViewController = Self.rootViewController() else {
            throw .googleSignInFailed("no root view controller to present Google sign-in from")
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.googleSignInFailed("Google sign-in returned no ID token")
            }
            return idToken
        } catch let error as GIDSignInError where error.code == .canceled {
            throw .googleSignInCancelled
        } catch let error as AuthError {
            throw error
        } catch {
            throw .googleSignInFailed(error.localizedDescription)
        }
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
