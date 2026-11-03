import Foundation
import Testing
@testable import StravaClone

/// "Ajoute une photo de profil" (ADR-037 §2, ADR-035 §1 amended): after the sign-in and before
/// the Paywall, on the Onboarding path, only for an account the email code has just created.
/// "Choisir une photo" and "Plus tard" both lead to the Paywall; the screen never comes back.
@MainActor
struct AuthStoreAvatarPromptTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_793_607_330)

    private let repository = FakeAuthRepository()
    private let google = FakeGoogleAuthProvider()
    private let analytics = FakeAnalyticsClient()
    /// Created by the sign-in itself.
    private let newAda = AuthUser(id: "u1", email: "a@b.com", name: "Ada Lovelace", createdAt: now)
    /// Created a day before.
    private let ada = AuthUser(id: "u1", email: "a@b.com", name: "Ada Lovelace", createdAt: now - 86_400)

    private func makeAuthStore() -> AuthStore {
        AuthStore(
            service: AuthService(repository: repository, googleAuthProvider: google),
            analytics: analytics,
            sleep: ManualSleeper().sleep,
            notificationPermission: FakeNotificationPermission(status: .denied),
            now: { Self.now }
        )
    }

    private func signInWithACode(_ authStore: AuthStore, entry: SignInEntry, as user: AuthUser) async {
        repository.sendSignInCodeHandler = { _ in }
        repository.signInHandler = { _, _, _ in user }
        let signIn = authStore.makeSignInStore(entry: entry)
        signIn.email = "a@b.com"
        await signIn.sendCode()
        signIn.enterCode("123456")
        _ = await eventually { authStore.state != .checkingSession }
    }

    private func signInWithGoogle(_ authStore: AuthStore, entry: SignInEntry, as user: AuthUser) async {
        google.signInHandler = { "id-token" }
        repository.signInWithGoogleHandler = { _ in user }
        await authStore.makeSignInStore(entry: entry).signInWithGoogle()
        _ = await eventually { authStore.state != .checkingSession }
    }

    // MARK: Who sees it

    @Test func aCodeThatCreatesTheAccountAtTheEndOfTheOnboardingShowsThePromptThenThePaywall() async {
        let authStore = makeAuthStore()

        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: newAda)

        #expect(authStore.state == .avatarPrompt(newAda))
        #expect(analytics.names.suffix(2) == ["signed_in", "avatar_prompt_viewed"])

        authStore.deferAvatarPrompt()

        #expect(authStore.state == .paywall(newAda))
    }

    @Test func finishingTheOnboardingThatSeConnecterOpenedOnANewAccountShowsThePrompt() async {
        let authStore = makeAuthStore()
        await signInWithACode(authStore, entry: .signIn, as: newAda)
        #expect(authStore.state == .onboarding(newAda))
        #expect(!analytics.names.contains("avatar_prompt_viewed"))

        authStore.finishOnboarding()

        #expect(authStore.state == .avatarPrompt(newAda))
        #expect(analytics.names.last == "avatar_prompt_viewed")
    }

    /// A Google account already has its photo (ADR-037 §2): straight to the Paywall.
    @Test func aGoogleAccountGoesStraightToThePaywall() async {
        let authStore = makeAuthStore()

        await signInWithGoogle(authStore, entry: .onboarding(name: "Ada Lovelace"), as: newAda)

        #expect(authStore.state == .paywall(newAda))
        #expect(!analytics.names.contains("avatar_prompt_viewed"))
    }

    @Test func aGoogleAccountThatSeConnecterCreatedGoesStraightToThePaywallAfterTheOnboarding() async {
        let authStore = makeAuthStore()
        await signInWithGoogle(authStore, entry: .signIn, as: newAda)
        #expect(authStore.state == .onboarding(newAda))

        authStore.finishOnboarding()

        #expect(authStore.state == .paywall(newAda))
        #expect(!analytics.names.contains("avatar_prompt_viewed"))
    }

    /// The code signs in to an account that existed before the Onboarding: no prompt.
    @Test func aCodeForAnExistingAccountAtTheEndOfTheOnboardingGoesStraightToThePaywall() async {
        let authStore = makeAuthStore()

        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: ada)

        #expect(authStore.state == .paywall(ada))
        #expect(!analytics.names.contains("avatar_prompt_viewed"))
    }

    @Test func seConnecterOnAnExistingAccountGoesHomeWithoutThePrompt() async {
        let authStore = makeAuthStore()

        await signInWithACode(authStore, entry: .signIn, as: ada)

        #expect(authStore.state == .signedIn(ada))
        #expect(!analytics.names.contains("avatar_prompt_viewed"))
    }

    // MARK: Leaving it

    @Test func plusTardIsDeferredThenThePaywall() async {
        let authStore = makeAuthStore()
        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: newAda)

        authStore.deferAvatarPrompt()

        #expect(authStore.state == .paywall(newAda))
        #expect(analytics.names.suffix(2) == ["avatar_prompt_viewed", "avatar_prompt_deferred"])
    }

    /// The photo is stored (`avatar_changed` comes from the editor): the Paywall, nothing deferred.
    @Test func aChosenPhotoLeadsToThePaywall() async {
        let authStore = makeAuthStore()
        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: newAda)

        authStore.finishAvatarPrompt()

        #expect(authStore.state == .paywall(newAda))
        #expect(analytics.names.last == "avatar_prompt_viewed")
    }

    @Test func thePromptNeverComesBack() async {
        let authStore = makeAuthStore()
        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: newAda)
        authStore.deferAvatarPrompt()
        let events = analytics.events

        authStore.deferAvatarPrompt()
        authStore.finishAvatarPrompt()
        #expect(authStore.state == .paywall(newAda))

        await authStore.finishPaywall()
        authStore.finishAvatarPrompt()

        #expect(authStore.state == .signedIn(newAda))
        #expect(analytics.events == events)
    }

    /// The app killed on the prompt: the next launch goes home, it is not resumed.
    @Test func aRestoredSessionGoesHomeWithoutThePrompt() async {
        let authStore = makeAuthStore()
        repository.currentUserHandler = { [newAda] in newAda }

        await authStore.restoreSession()

        #expect(authStore.state == .signedIn(newAda))
        #expect(analytics.events.isEmpty)
    }
}
