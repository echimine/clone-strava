import Foundation

extension SignInStore {
    /// What the account screen or the code screen could not do, other than a refused code
    /// (`CodeProblem`).
    enum FormError: Equatable {
        case rateLimited
        case offline
        /// A server-provided message (AuthError.server) or a Google-specific failure —
        /// shown verbatim rather than folded into a generic "something went wrong".
        case message(String)

        init(_ error: AuthError) {
            switch error {
            case .rateLimited: self = .rateLimited
            case .server(let message): self = .message(message)
            case .network(.offline): self = .offline
            case .network(let apiError): self = .message(FormError.describe(apiError))
            case .googleSignInFailed(let message): self = .message("Google : \(message)")
            // Handled by the store before they get here (refused code, cancelled Google sheet).
            case .notSignedIn, .invalidCode, .codeExpired, .tooManyAttempts, .googleSignInCancelled:
                self = .message("")
            }
        }

        /// The displayed, non-technical message (French).
        var text: String {
            switch self {
            case .rateLimited: "Trop de tentatives, réessayez dans une minute."
            case .offline: "Pas de connexion internet."
            case .message(let message): message.isEmpty ? "Une erreur est survenue, réessayez." : message
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
}
