import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class ASAuthorizationAppleProvider: NSObject, AppleAuthProvider {
    private var continuation: CheckedContinuation<String, any Error>?
    private var currentNonce: String?

    func signIn() async throws(AuthError) -> String {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let nonce = Self.randomNonce()
                currentNonce = nonce
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.email, .fullName]
                request.nonce = Self.sha256(nonce)
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw .appleSignInCancelled
        } catch let error as AuthError {
            throw error
        } catch {
            throw .appleSignInFailed(error.localizedDescription)
        }
    }

    private static func randomNonce() -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<32).compactMap { _ in chars.randomElement() })
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension ASAuthorizationAppleProvider: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            continuation?.resume(throwing: AuthError.appleSignInFailed("Jeton Apple absent"))
            continuation = nil
            return
        }
        continuation?.resume(returning: token)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
