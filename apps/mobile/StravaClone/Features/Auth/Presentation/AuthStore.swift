import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case checkingSession
        case signedOut
        case signedIn(AuthUser)
    }

    enum FormError: Equatable {
        case invalidCredentials
        case emailAlreadyInUse
        case rateLimited
        case offline
        /// A server-provided message (AuthError.server) or a Google-specific failure —
        /// shown verbatim rather than folded into a generic "something went wrong".
        case message(String)

        init(_ error: AuthError) {
            switch error {
            case .invalidCredentials: self = .invalidCredentials
            case .emailAlreadyInUse: self = .emailAlreadyInUse
            case .rateLimited: self = .rateLimited
            case .server(let message): self = .message(message)
            case .network(.offline): self = .offline
            case .network(let apiError): self = .message(FormError.describe(apiError))
            case .googleSignInFailed(let message): self = .message("Google : \(message)")
            case .googleSignInCancelled: self = .message("") // never surfaced, see run(_:)
            }
        }

        /// A short, non-technical description of a lower-level network failure — the
        /// cases that don't have a server message to show (transport error, decoding
        /// failure, an unmapped HTTP status).
        private static func describe(_ error: APIError) -> String {
            switch error {
            case .offline: "Pas de connexion internet."
            case .unauthorized: "Session expirée, reconnectez-vous."
            case .decoding: "Réponse du serveur illisible."
            case .transport: "Impossible de joindre le serveur."
            case .http(let status, _): "Erreur serveur (code \(status))."
            }
        }
    }

    private(set) var state = State.checkingSession
    private(set) var formError: FormError?
    private(set) var isSubmitting = false

    @ObservationIgnored private let service: AuthService

    init(service: AuthService) {
        self.service = service
    }

    func restoreSession() async {
        if let user = await service.restoreSession() {
            state = .signedIn(user)
        } else {
            state = .signedOut
        }
    }

    func signUp(email: String, password: String, name: String) async {
        await run { try await self.service.signUp(email: email, password: password, name: name) }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.service.signIn(email: email, password: password) }
    }

    func signInWithGoogle() async {
        await run(
            { try await self.service.signInWithGoogle() },
            // Cancelling the Google sheet is a no-op, not an error to surface.
            suppressing: .googleSignInCancelled
        )
    }

    func signOut() async {
        await service.signOut()
        state = .signedOut
    }

    private func run(
        _ action: @escaping () async throws -> AuthUser,
        suppressing suppressed: AuthError? = nil
    ) async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }
        do {
            state = .signedIn(try await action())
        } catch let error as AuthError {
            if error != suppressed {
                formError = FormError(error)
            }
        } catch {
            formError = .message(String(describing: error))
        }
    }
}
