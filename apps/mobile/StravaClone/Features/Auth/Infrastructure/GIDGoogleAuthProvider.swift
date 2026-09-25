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

    /// The key window's root view controller, walked down to whatever it is currently
    /// presenting — GIDSignIn must be presented from the top-most visible controller,
    /// or the presented sheet can be torn down mid-load (observed as "Attempting to
    /// load the view of a view controller while it is deallocating").
    private static func rootViewController() -> UIViewController? {
        guard var top = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
