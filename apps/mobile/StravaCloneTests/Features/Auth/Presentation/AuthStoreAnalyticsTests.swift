import Foundation
import Testing
@testable import StravaClone

/// The analytics identity follows the session (ADR-035 §8): `identify` as soon as a session
/// exists (after the code, after Google, at launch), `reset()` at sign-out, and the Measurement
/// consent, kept on the phone, survives the sign-out.
@MainActor
struct AuthStoreAnalyticsTests {
    struct Harness {
        let authStore: AuthStore
        let repository: FakeAuthRepository
        let google: FakeGoogleAuthProvider
        let analytics: FakeAnalyticsClient
    }

    private let ada = AuthUser(id: "u1", email: "a@b.com", name: "Ada")

    private func makeHarness() -> Harness {
        let repository = FakeAuthRepository()
        let google = FakeGoogleAuthProvider()
        let analytics = FakeAnalyticsClient()
        let service = AuthService(repository: repository, googleAuthProvider: google)
        let authStore = AuthStore(service: service, analytics: analytics, sleep: ManualSleeper().sleep)
        return Harness(authStore: authStore, repository: repository, google: google, analytics: analytics)
    }

    @Test func aLaunchWithASessionIdentifiesIt() async {
        let harness = makeHarness()
        harness.repository.currentUserHandler = { [ada] in ada }

        await harness.authStore.restoreSession()

        #expect(harness.analytics.calls == [.identify(userId: "u1")])
    }

    @Test func aLaunchWithoutASessionIdentifiesNobody() async {
        let harness = makeHarness()
        harness.repository.currentUserHandler = { () throws(AuthError) in throw .notSignedIn }

        await harness.authStore.restoreSession()

        #expect(harness.analytics.calls.isEmpty)
    }

    @Test func signingInWithACodeIdentifiesTheAccount() async {
        let harness = makeHarness()
        harness.repository.sendSignInCodeHandler = { _ in }
        harness.repository.signInHandler = { [ada] _, _, _ in ada }
        let signIn = harness.authStore.makeSignInStore()
        signIn.email = "a@b.com"
        await signIn.sendCode()

        signIn.enterCode("123456")

        #expect(await eventually { harness.authStore.state == .signedIn(ada) })
        #expect(harness.analytics.calls == [.identify(userId: "u1")])
    }

    @Test func signingInWithGoogleIdentifiesTheAccount() async {
        let harness = makeHarness()
        harness.google.signInHandler = { "id-token" }
        harness.repository.signInWithGoogleHandler = { [ada] _ in ada }

        await harness.authStore.makeSignInStore().signInWithGoogle()

        #expect(harness.analytics.calls == [.identify(userId: "u1")])
    }

    @Test func signingOutResetsTheIdentityButKeepsTheMeasurementConsent() async {
        let harness = makeHarness()
        harness.repository.currentUserHandler = { [ada] in ada }
        harness.repository.signOutHandler = {}
        let preferences = InMemoryConsentPreferences(consent: .accepted)
        await harness.authStore.restoreSession()

        await harness.authStore.signOut()

        #expect(harness.analytics.calls == [.identify(userId: "u1"), .reset])
        #expect(preferences.consent == .accepted)
        let consent = MeasurementConsentStore(preferences: preferences, analytics: harness.analytics, signedInUserID: { nil })
        #expect(consent.isMeasurementEnabled)
    }
}
