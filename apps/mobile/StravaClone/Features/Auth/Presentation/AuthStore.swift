import Foundation
import Observation

/// Who is signed in, for the whole app (ADR-022): `RootView` shows the account screen or the
/// TabView from `state`. Signing in itself happens on the account screen, in `SignInStore`.
@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case checkingSession
        case signedOut
        case signedIn(AuthUser)
    }

    private(set) var state = State.checkingSession

    @ObservationIgnored private let service: AuthService
    /// The account screen's clock (the 30 s before "Recevoir un nouveau code").
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    init(service: AuthService, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service
        self.sleep = sleep
    }

    /// The account screen's store; a sign-in there signs the app in. `name` is the account's
    /// name if the code creates it (filled by the Onboarding, ADR-035 §2).
    func makeSignInStore(name: String? = nil) -> SignInStore {
        SignInStore(service: service, name: name, sleep: sleep) { [weak self] user in
            self?.state = .signedIn(user)
        }
    }

    func restoreSession() async {
        if let user = await service.restoreSession() {
            state = .signedIn(user)
        } else {
            state = .signedOut
        }
    }

    func signOut() async {
        await service.signOut()
        state = .signedOut
    }
}
