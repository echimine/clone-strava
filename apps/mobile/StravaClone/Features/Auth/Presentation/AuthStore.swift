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
        case other(String)

        init(_ error: AuthError) {
            switch error {
            case .invalidCredentials: self = .invalidCredentials
            case .emailAlreadyInUse: self = .emailAlreadyInUse
            case .rateLimited: self = .rateLimited
            case .network(.offline): self = .offline
            case .network(let apiError): self = .other(String(describing: apiError))
            case .googleSignInFailed(let message): self = .other(message)
            case .googleSignInCancelled: self = .other("") // never surfaced, see run(_:)
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
            formError = .other(String(describing: error))
        }
    }
}
