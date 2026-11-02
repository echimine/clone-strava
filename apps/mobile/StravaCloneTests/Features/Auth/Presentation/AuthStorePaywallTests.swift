import Foundation
import Testing
@testable import StravaClone

/// The Paywall (ADR-035 §6): shown once, right after the sign-in that ends the Onboarding, never
/// on the "Se connecter" path, and not resumed after the app is killed.
@MainActor
struct AuthStorePaywallTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_793_607_330)

    private let repository = FakeAuthRepository()
    private let google = FakeGoogleAuthProvider()

    private func makeAuthStore() -> AuthStore {
        AuthStore(
            service: AuthService(repository: repository, googleAuthProvider: google),
            sleep: ManualSleeper().sleep,
            now: { Self.now }
        )
    }

    private func user(createdMinutesAgo minutes: Double) -> AuthUser {
        AuthUser(id: "u1", email: "a@b.com", name: "Ada Lovelace", createdAt: Self.now.addingTimeInterval(-minutes * 60))
    }

    private func signInWithACode(_ authStore: AuthStore, entry: SignInEntry, as user: AuthUser) async {
        repository.sendSignInCodeHandler = { _ in }
        repository.signInHandler = { _, _, _ in user }
        let signIn = authStore.makeSignInStore(entry: entry)
        signIn.email = "a@b.com"
        await signIn.sendCode()
        signIn.enterCode("123456")
    }

    @Test func signingInAtTheEndOfTheOnboardingShowsThePaywall() async {
        let authStore = makeAuthStore()
        let ada = user(createdMinutesAgo: 0)

        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: ada)

        #expect(await eventually { authStore.state == .paywall(ada) })
    }

    @Test func finishingTheOnboardingThatSeConnecterOpenedShowsThePaywall() async {
        let authStore = makeAuthStore()
        let ada = user(createdMinutesAgo: 1)
        await signInWithACode(authStore, entry: .signIn, as: ada)
        #expect(await eventually { authStore.state == .onboarding(ada) })

        authStore.finishOnboarding()

        #expect(authStore.state == .paywall(ada))
    }

    @Test func seConnecterOnAnExistingAccountNeverShowsThePaywall() async {
        let authStore = makeAuthStore()
        let ada = user(createdMinutesAgo: 3)

        await signInWithACode(authStore, entry: .signIn, as: ada)

        #expect(await eventually { authStore.state == .signedIn(ada) })
    }

    @Test func leavingThePaywallGoesHome() async {
        let authStore = makeAuthStore()
        let ada = user(createdMinutesAgo: 0)
        await signInWithACode(authStore, entry: .onboarding(name: "Ada Lovelace"), as: ada)
        #expect(await eventually { authStore.state == .paywall(ada) })

        await authStore.finishPaywall()

        #expect(authStore.state == .signedIn(ada))
    }

    /// The app killed on the Paywall: the next launch goes home, the Paywall is not resumed.
    @Test func aRestoredSessionGoesHomeWithoutThePaywall() async {
        let authStore = makeAuthStore()
        let ada = user(createdMinutesAgo: 0)
        repository.currentUserHandler = { ada }

        await authStore.restoreSession()

        #expect(authStore.state == .signedIn(ada))
    }
}
