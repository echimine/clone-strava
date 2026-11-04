import Foundation
import Observation

/// Who is signed in, for the whole app (ADR-022): `RootView` shows the Welcome, the Onboarding,
/// "Ajoute une photo de profil", the Paywall, the notification priming screen or the TabView
/// from `state`. Signing in itself happens on the account screen, in
/// `SignInStore`. The analytics identity follows the session (ADR-035 §8): `identify` as soon as
/// one exists, `reset()` at sign-out.
///
/// After a sign-in (ADR-035 §1, §5, §6): at the end of the Onboarding, the Onboarding answers are
/// sent, after `identify`, and the flow goes on to the Paywall without waiting for them. "Se
/// connecter" on an account it has just created goes through the Onboarding (and so the Paywall)
/// first; an existing account never does. Before the Paywall comes "Ajoute une photo de profil",
/// only for an account the email code has just created (ADR-037 §2: a Google account already
/// has its photo). After the Paywall comes the notification priming screen, only while iOS has
/// not asked yet (§7). A restored session always goes home: none of these screens is resumed.
///
/// It sends the funnel events around the session (§8): `welcome_viewed`, `onboarding_started`,
/// `signed_in` right after `identify`, those of the photo screen (ADR-037 §13) and those of the
/// priming screen.
@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case checkingSession
        case signedOut
        /// Signed in by "Se connecter" on an account it has just created: the Onboarding, from
        /// its first question, before the home screen.
        case onboarding(AuthUser)
        /// After the sign-in that ends the Onboarding, for an account the email code has just
        /// created (ADR-037 §2): "Ajoute une photo de profil", once, then the Paywall.
        case avatarPrompt(AuthUser)
        /// Right after the sign-in that ends the Onboarding (ADR-035 §6): the Paywall, once.
        case paywall(AuthUser)
        /// After that Paywall, while iOS has not asked for the notification permission yet
        /// (ADR-035 §7): Nervo's priming screen, once.
        case notificationPrimer(AuthUser)
        case signedIn(AuthUser)
    }

    private(set) var state = State.checkingSession
    /// iOS's prompt is open: a second tap on "Activer les notifications" does nothing.
    private(set) var isRequestingNotifications = false
    /// The last sign-in created the account (`AuthUser.isNewAccount`), for the Paywall's events.
    private(set) var isNewAccount = false
    /// How the last sign-in was made: only an email code leads to the photo screen.
    @ObservationIgnored private var signInMethod: AnalyticsEvent.AuthMethod?

    @ObservationIgnored private let service: AuthService
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// The account screen's clock (the 30 s before "Recevoir un nouveau code").
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// Sends the Onboarding answers of the draft (ADR-035 §5); never awaited by the flow.
    @ObservationIgnored private let submitOnboardingAnswers: @MainActor () async -> Void
    /// Whether the priming screen follows the Paywall, and the system prompt it opens.
    @ObservationIgnored private let notificationPermission: any NotificationPermission
    @ObservationIgnored private let now: @Sendable () -> Date

    init(
        service: AuthService,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        submitOnboardingAnswers: @escaping @MainActor () async -> Void = {},
        notificationPermission: any NotificationPermission = SettledNotificationPermission(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.analytics = analytics
        self.sleep = sleep
        self.submitOnboardingAnswers = submitOnboardingAnswers
        self.notificationPermission = notificationPermission
        self.now = now
    }

    /// The account screen's store; a sign-in there signs the app in.
    func makeSignInStore(entry: SignInEntry = .signIn) -> SignInStore {
        SignInStore(service: service, entry: entry, analytics: analytics, sleep: sleep) { [weak self] user, method in
            self?.signedIn(user, entry: entry, method: method)
        }
    }

    /// The Welcome is on screen, once the splash is gone.
    func welcomeViewed() {
        analytics.capture(.welcomeViewed)
    }

    /// "Créer un compte" on the Welcome.
    func onboardingStarted() {
        analytics.capture(.onboardingStarted)
    }

    /// "Créer mon compte" at the end of the Onboarding that "Se connecter" opened: the session
    /// exists already, so the answers are sent straight away, then the photo screen or the
    /// Paywall.
    func finishOnboarding() {
        guard case .onboarding(let user) = state else { return }
        startSubmittingOnboardingAnswers()
        showAvatarPromptOrPaywall(user)
    }

    /// The photo chosen on "Ajoute une photo de profil" is stored: the Paywall.
    func finishAvatarPrompt() {
        guard case .avatarPrompt(let user) = state else { return }
        state = .paywall(user)
    }

    /// "Plus tard" on "Ajoute une photo de profil": the Paywall. Nothing asks again.
    func deferAvatarPrompt() {
        guard case .avatarPrompt(let user) = state else { return }
        analytics.capture(.avatarPromptDeferred)
        state = .paywall(user)
    }

    /// The Paywall is left (trial tapped, skipped, or offers unavailable): the priming screen if
    /// iOS has not asked for the notification permission yet, else silently the home screen.
    func finishPaywall() async {
        guard case .paywall = state else { return }
        let status = await notificationPermission.status()
        guard case .paywall(let user) = state else { return }
        guard status == .notDetermined else {
            state = .signedIn(user)
            return
        }
        state = .notificationPrimer(user)
        analytics.capture(.notificationPromptViewed)
    }

    /// "Activer les notifications" on the priming screen: iOS's prompt, then home, whatever the
    /// answer.
    func enableNotifications() async {
        guard case .notificationPrimer = state, !isRequestingNotifications else { return }
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        let granted = await notificationPermission.requestAuthorization()
        analytics.capture(.notificationPermissionAnswered(granted: granted))
        guard case .notificationPrimer(let user) = state else { return }
        state = .signedIn(user)
    }

    /// "Plus tard": home, without spending iOS's one-time prompt. Nothing asks again.
    func deferNotifications() {
        guard case .notificationPrimer(let user) = state, !isRequestingNotifications else { return }
        analytics.capture(.notificationPermissionDeferred)
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

    private func signedIn(_ user: AuthUser, entry: SignInEntry, method: AnalyticsEvent.AuthMethod) {
        analytics.identify(userId: user.id)
        isNewAccount = user.isNewAccount(at: now())
        signInMethod = method
        analytics.capture(.signedIn(method: method, isNewAccount: isNewAccount))
        switch entry {
        case .onboarding:
            startSubmittingOnboardingAnswers()
            showAvatarPromptOrPaywall(user)
        case .signIn where isNewAccount:
            state = .onboarding(user)
        case .signIn:
            state = .signedIn(user)
        }
    }

    /// The end of the Onboarding path: the photo screen for an account the email code has just
    /// created, else the Paywall.
    private func showAvatarPromptOrPaywall(_ user: AuthUser) {
        guard isNewAccount, signInMethod == .email else {
            state = .paywall(user)
            return
        }
        state = .avatarPrompt(user)
        analytics.capture(.avatarPromptViewed)
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
