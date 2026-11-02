import Foundation
import Testing
@testable import StravaClone

/// The getting-started funnel around the session (ADR-035 §8), through `AuthStore` and the
/// `SignInStore` it makes: the Welcome, the account screen, the Sign-in code, Google, the
/// session, and the notification priming screen. Nothing is sent after "Refuser", and no event
/// carries a name or an email.
@MainActor
struct AuthFunnelAnalyticsTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_793_607_330)

    struct Harness {
        let authStore: AuthStore
        let repository: FakeAuthRepository
        let google: FakeGoogleAuthProvider
        let analytics: FakeAnalyticsClient
    }

    /// Created by the sign-in itself.
    private let newAda = AuthUser(id: "u1", email: "ada@lovelace.dev", name: "Ada Lovelace", createdAt: now)
    /// Created a day before.
    private let ada = AuthUser(id: "u1", email: "ada@lovelace.dev", name: "Ada Lovelace", createdAt: now - 86_400)

    private func makeHarness(
        permission: FakeNotificationPermission = FakeNotificationPermission(status: .denied)
    ) -> Harness {
        let repository = FakeAuthRepository()
        let google = FakeGoogleAuthProvider()
        let analytics = FakeAnalyticsClient()
        let authStore = AuthStore(
            service: AuthService(repository: repository, googleAuthProvider: google),
            analytics: analytics,
            sleep: ManualSleeper().sleep,
            notificationPermission: permission,
            now: { Self.now }
        )
        return Harness(authStore: authStore, repository: repository, google: google, analytics: analytics)
    }

    /// "Continuer" with Ada's address: the code screen.
    private func onTheCodeScreen(_ harness: Harness, entry: SignInEntry = .signIn) async -> SignInStore {
        harness.repository.sendSignInCodeHandler = { _ in }
        let signIn = harness.authStore.makeSignInStore(entry: entry)
        signIn.email = "ada@lovelace.dev"
        await signIn.sendCode()
        return signIn
    }

    private func signInWithCode(_ harness: Harness, as user: AuthUser, entry: SignInEntry = .signIn) async {
        harness.repository.signInHandler = { _, _, _ in user }
        let signIn = await onTheCodeScreen(harness, entry: entry)
        signIn.enterCode("123456")
        _ = await eventually { harness.authStore.state != .checkingSession }
    }

    // MARK: Welcome

    @Test func theWelcomeIsViewedThenCreateAnAccountStartsTheOnboarding() {
        let harness = makeHarness()

        harness.authStore.welcomeViewed()
        harness.authStore.onboardingStarted()

        #expect(harness.analytics.events == [.welcomeViewed, .onboardingStarted])
    }

    // MARK: Account screen

    @Test(arguments: [
        (SignInEntry.signIn, AnalyticsEvent.AuthEntry.signIn),
        (.onboarding(name: "Ada Lovelace"), .create),
    ])
    func theAccountScreenIsViewedWithItsEntry(entry: SignInEntry, expected: AnalyticsEvent.AuthEntry) {
        let harness = makeHarness()

        harness.authStore.makeSignInStore(entry: entry).viewed()

        #expect(harness.analytics.events == [.authScreenViewed(entry: expected)])
        #expect(harness.analytics.events.first?.properties == ["entry": .string(expected.rawValue)])
    }

    @Test func continueChoosesTheEmailAndRequestsACode() async {
        let harness = makeHarness()

        _ = await onTheCodeScreen(harness)

        #expect(harness.analytics.events == [.authMethodChosen(method: .email), .emailCodeRequested(resend: false)])
    }

    @Test func aCodeThatCannotBeSentIsNotRequested() async {
        let harness = makeHarness()
        harness.repository.sendSignInCodeHandler = { _ throws(AuthError) in throw .rateLimited }
        let signIn = harness.authStore.makeSignInStore()
        signIn.email = "ada@lovelace.dev"

        await signIn.sendCode()

        #expect(harness.analytics.names == ["auth_method_chosen"])
    }

    @Test(arguments: [
        (AuthError.invalidCode, AnalyticsEvent.CodeFailure.incorrect),
        (.codeExpired, .expired),
        (.tooManyAttempts, .tooManyAttempts),
        (.network(.offline), .network),
    ])
    func aRefusedCodeFailsWithItsReason(error: AuthError, reason: AnalyticsEvent.CodeFailure) async {
        let harness = makeHarness()
        harness.repository.signInHandler = { _, _, _ throws(AuthError) in throw error }
        let signIn = await onTheCodeScreen(harness)

        signIn.enterCode("123456")

        #expect(await eventually { harness.analytics.events.last == .emailCodeFailed(reason: reason) })
        #expect(harness.analytics.events.last?.properties == ["reason": .string(reason.rawValue)])
    }

    /// The server answers the 3rd wrong code with `INVALID_OTP` too, but that code is spent.
    @Test func theThirdWrongCodeFailsWithTooManyAttempts() async {
        let harness = makeHarness()
        harness.repository.signInHandler = { _, _, _ throws(AuthError) in throw .invalidCode }
        let signIn = await onTheCodeScreen(harness)

        for attempt in 1...SignInStore.attemptsPerCode {
            signIn.enterCode("123456")
            _ = await eventually { harness.analytics.names.filter { $0 == "email_code_failed" }.count == attempt }
        }

        let failures = harness.analytics.events.filter { if case .emailCodeFailed = $0 { true } else { false } }
        #expect(failures == [
            .emailCodeFailed(reason: .incorrect),
            .emailCodeFailed(reason: .incorrect),
            .emailCodeFailed(reason: .tooManyAttempts),
        ])
    }

    @Test func aNewCodeIsRequestedAsAResend() async {
        let harness = makeHarness()
        harness.repository.signInHandler = { _, _, _ throws(AuthError) in throw .codeExpired }
        let signIn = await onTheCodeScreen(harness)
        signIn.enterCode("123456")
        _ = await eventually { signIn.canResendCode }

        await signIn.resendCode()

        #expect(harness.analytics.events.last == .emailCodeRequested(resend: true))
    }

    @Test func closingGoogleChoosesGoogleThenCancelsIt() async {
        let harness = makeHarness()
        harness.google.signInHandler = { () throws(AuthError) in throw .googleSignInCancelled }

        await harness.authStore.makeSignInStore().signInWithGoogle()

        #expect(harness.analytics.events == [.authMethodChosen(method: .google), .authGoogleCancelled])
    }

    // MARK: Session

    @Test func aCodeThatCreatesTheAccountSignsInANewAccountByEmail() async {
        let harness = makeHarness()

        await signInWithCode(harness, as: newAda)

        #expect(harness.analytics.events.last == .signedIn(method: .email, isNewAccount: true))
        #expect(harness.analytics.events.last?.properties == ["method": "email", "isNewAccount": true])
        #expect(harness.analytics.calls == [.identify(userId: "u1")])
    }

    @Test func aCodeForAnExistingAccountSignsItIn() async {
        let harness = makeHarness()

        await signInWithCode(harness, as: ada, entry: .onboarding(name: "Ada Lovelace"))

        #expect(harness.analytics.events.last == .signedIn(method: .email, isNewAccount: false))
    }

    @Test func googleSignsIn() async {
        let harness = makeHarness()
        harness.google.signInHandler = { "id-token" }
        harness.repository.signInWithGoogleHandler = { [newAda] _ in newAda }

        await harness.authStore.makeSignInStore().signInWithGoogle()

        #expect(harness.analytics.events == [
            .authMethodChosen(method: .google),
            .signedIn(method: .google, isNewAccount: true),
        ])
    }

    @Test func thePaywallKnowsWhetherTheAccountIsNew() async {
        let harness = makeHarness()

        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))

        #expect(harness.authStore.state == .paywall(newAda))
        #expect(harness.authStore.isNewAccount)
    }

    // MARK: Notification priming screen

    @Test func thePrimerIsViewedThenTheSystemPromptAnswered() async {
        let harness = makeHarness(permission: FakeNotificationPermission(status: .notDetermined, answer: false))
        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))

        await harness.authStore.finishPaywall()
        await harness.authStore.enableNotifications()

        #expect(Array(harness.analytics.events.suffix(2)) == [
            .notificationPromptViewed,
            .notificationPermissionAnswered(granted: false),
        ])
    }

    @Test func plusTardDefersThePermission() async {
        let harness = makeHarness(permission: FakeNotificationPermission(status: .notDetermined))
        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))
        await harness.authStore.finishPaywall()

        harness.authStore.deferNotifications()

        #expect(Array(harness.analytics.names.suffix(2)) == [
            "notification_prompt_viewed", "notification_permission_deferred",
        ])
    }

    @Test func aSkippedPrimerSendsNothing() async {
        let harness = makeHarness(permission: FakeNotificationPermission(status: .granted))
        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))
        let before = harness.analytics.events

        await harness.authStore.finishPaywall()

        #expect(harness.authStore.state == .signedIn(newAda))
        #expect(harness.analytics.events == before)
    }

    // MARK: Consent and personal data

    @Test func nothingIsSentAfterRefuser() async {
        let harness = makeHarness(permission: FakeNotificationPermission(status: .notDetermined))
        let consent = MeasurementConsentStore(
            preferences: InMemoryConsentPreferences(),
            analytics: harness.analytics,
            signedInUserID: { nil }
        )
        consent.refuse()

        harness.authStore.welcomeViewed()
        harness.authStore.onboardingStarted()
        harness.authStore.makeSignInStore(entry: .onboarding(name: "Ada Lovelace")).viewed()
        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))
        await harness.authStore.finishPaywall()
        await harness.authStore.enableNotifications()

        #expect(harness.authStore.state == .signedIn(newAda))
        #expect(harness.analytics.events.isEmpty)
    }

    @Test func noEventCarriesTheNameOrTheEmail() async {
        let harness = makeHarness(permission: FakeNotificationPermission(status: .notDetermined))
        harness.authStore.welcomeViewed()
        harness.authStore.makeSignInStore(entry: .onboarding(name: "Ada Lovelace")).viewed()
        await signInWithCode(harness, as: newAda, entry: .onboarding(name: "Ada Lovelace"))
        await harness.authStore.finishPaywall()
        harness.authStore.deferNotifications()

        #expect(harness.analytics.events.count >= 6)
        for event in harness.analytics.events {
            for (key, value) in event.properties {
                #expect(!["name", "email", "emailDomain", "domain"].contains(key))
                if case .string(let text) = value {
                    #expect(!["Ada", "Lovelace", "lovelace.dev", "@"].contains { text.contains($0) })
                }
            }
        }
    }
}
