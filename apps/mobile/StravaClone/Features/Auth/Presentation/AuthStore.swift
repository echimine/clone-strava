import Foundation
import Observation

/// Who is signed in, for the whole app (ADR-022): `RootView` shows the Welcome, the Onboarding,
/// the Paywall or the TabView from `state`. Signing in itself happens on the account screen, in
/// `SignInStore`. The analytics identity follows the session (ADR-035 §8): `identify` as soon as
/// one exists, `reset()` at sign-out.
///
/// After a sign-in (ADR-035 §1, §5, §6): at the end of the Onboarding, the Onboarding answers are
/// sent, after `identify`, and the flow goes on to the Paywall without waiting for them. "Se
/// connecter" on an account it has just created goes through the Onboarding (and so the Paywall)
/// first; an existing account never does. A restored session always goes home: the Paywall is
/// not resumed.
@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case checkingSession
        case signedOut
        /// Signed in by "Se connecter" on an account it has just created: the Onboarding, from
        /// its first question, before the home screen.
        case onboarding(AuthUser)
        /// Right after the sign-in that ends the Onboarding (ADR-035 §6): the Paywall, once.
        case paywall(AuthUser)
        case signedIn(AuthUser)
    }

    private(set) var state = State.checkingSession

    @ObservationIgnored private let service: AuthService
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// The account screen's clock (the 30 s before "Recevoir un nouveau code").
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// Sends the Onboarding answers of the draft (ADR-035 §5); never awaited by the flow.
    @ObservationIgnored private let submitOnboardingAnswers: @MainActor () async -> Void
    @ObservationIgnored private let now: @Sendable () -> Date

    init(
        service: AuthService,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        submitOnboardingAnswers: @escaping @MainActor () async -> Void = {},
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.analytics = analytics
        self.sleep = sleep
        self.submitOnboardingAnswers = submitOnboardingAnswers
        self.now = now
    }

    /// The account screen's store; a sign-in there signs the app in.
    func makeSignInStore(entry: SignInEntry = .signIn) -> SignInStore {
        SignInStore(service: service, name: entry.accountName, sleep: sleep) { [weak self] user in
            self?.signedIn(user, entry: entry)
        }
    }

    /// "Créer mon compte" at the end of the Onboarding that "Se connecter" opened: the session
    /// exists already, so the answers are sent straight away, then the Paywall.
    func finishOnboarding() {
        guard case .onboarding(let user) = state else { return }
        startSubmittingOnboardingAnswers()
        state = .paywall(user)
    }

    /// The Paywall is left (trial tapped, skipped, or offers unavailable): the home screen.
    func finishPaywall() {
        guard case .paywall(let user) = state else { return }
        state = .signedIn(user)
    }

    func restoreSession() async {
        if let user = await service.restoreSession() {
            analytics.identify(userId: user.id)
            state = .signedIn(user)
        } else {
            state = .signedOut
        }
    }

    func signOut() async {
        await service.signOut()
        analytics.reset()
        state = .signedOut
    }

    private func signedIn(_ user: AuthUser, entry: SignInEntry) {
        analytics.identify(userId: user.id)
        switch entry {
        case .onboarding:
            startSubmittingOnboardingAnswers()
            state = .paywall(user)
        case .signIn where user.isNewAccount(at: now()):
            state = .onboarding(user)
        case .signIn:
            state = .signedIn(user)
        }
    }

    private func startSubmittingOnboardingAnswers() {
        Task { await submitOnboardingAnswers() }
    }
}

/// Where the account screen was opened from (ADR-035 §1).
enum SignInEntry: Equatable, Sendable {
    /// "Se connecter" on the Welcome.
    case signIn
    /// The end of the Onboarding: `name` ("Prénom Nom") names the account if the code creates it
    /// (ADR-035 §2).
    case onboarding(name: String)

    var accountName: String? {
        if case .onboarding(let name) = self, !name.isEmpty { name } else { nil }
    }
}
