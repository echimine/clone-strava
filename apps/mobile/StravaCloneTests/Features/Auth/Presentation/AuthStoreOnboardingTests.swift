import Foundation
import Testing
@testable import StravaClone

/// What follows a sign-in (ADR-035 §1, §5): at the end of the Onboarding the answers are sent
/// without the flow waiting for them, and the Paywall follows; "Se connecter" on an account it has just created goes
/// through the Onboarding, an existing account never does.
@MainActor
struct AuthStoreOnboardingTests {
    struct Harness {
        let authStore: AuthStore
        let repository: FakeAuthRepository
        let google: FakeGoogleAuthProvider
        let analytics: FakeAnalyticsClient
        /// Holds each submission until `wakeAll()`, as a request that has not answered yet.
        let pendingRequest: ManualSleeper
        let submissions: Locked<[[FakeAnalyticsClient.Call]]>
    }

    nonisolated private static let now = Date(timeIntervalSince1970: 1_793_607_330)

    private func makeHarness() -> Harness {
        let repository = FakeAuthRepository()
        let google = FakeGoogleAuthProvider()
        let analytics = FakeAnalyticsClient()
        let pendingRequest = ManualSleeper()
        // The analytics calls already made when each submission starts.
        let submissions = Locked<[[FakeAnalyticsClient.Call]]>([])
        let authStore = AuthStore(
            service: AuthService(repository: repository, googleAuthProvider: google),
            analytics: analytics,
            sleep: ManualSleeper().sleep,
            submitOnboardingAnswers: {
                submissions.value.append(analytics.calls)
                try? await pendingRequest.sleep(.zero)
            },
            now: { Self.now }
        )
        return Harness(
            authStore: authStore,
            repository: repository,
            google: google,
            analytics: analytics,
            pendingRequest: pendingRequest,
            submissions: submissions
        )
    }

    private func user(createdMinutesAgo minutes: Double) -> AuthUser {
        AuthUser(id: "u1", email: "a@b.com", name: "Ada", createdAt: Self.now.addingTimeInterval(-minutes * 60))
    }

    private func signInWithACode(_ harness: Harness, entry: SignInEntry, as user: AuthUser) async {
        harness.repository.sendSignInCodeHandler = { _ in }
        harness.repository.signInHandler = { _, _, _ in user }
        let signIn = harness.authStore.makeSignInStore(entry: entry)
        signIn.email = "a@b.com"
        await signIn.sendCode()
        signIn.enterCode("123456")
    }

    // MARK: The end of the Onboarding

    @Test func signingInAtTheEndOfTheOnboardingGoesOnWithoutWaitingForTheAnswersToBeSent() async {
        let harness = makeHarness()
        let ada = user(createdMinutesAgo: 0)

        await signInWithACode(harness, entry: .onboarding(name: "Ada Lovelace"), as: ada)

        #expect(await eventually { harness.authStore.state == .paywall(ada) })
        #expect(harness.submissions.value.count == 1)
        #expect(harness.pendingRequest.waiting == 1)
        harness.pendingRequest.wakeAll()
    }

    @Test func theAccountIsIdentifiedBeforeTheAnswersAreSent() async {
        let harness = makeHarness()
        harness.google.signInHandler = { "id-token" }
        harness.repository.signInWithGoogleHandler = { [ada = user(createdMinutesAgo: 0)] _ in ada }

        await harness.authStore.makeSignInStore(entry: .onboarding(name: "Ada Lovelace")).signInWithGoogle()

        #expect(await eventually { harness.submissions.value == [[.identify(userId: "u1")]] })
        harness.pendingRequest.wakeAll()
    }

    // MARK: "Se connecter"

    @Test func signingInOnAnAccountCreatedAMinuteAgoGoesThroughTheOnboarding() async {
        let harness = makeHarness()
        let ada = user(createdMinutesAgo: 1)

        await signInWithACode(harness, entry: .signIn, as: ada)

        #expect(await eventually { harness.authStore.state == .onboarding(ada) })
        #expect(harness.submissions.value.isEmpty)
    }

    @Test func signingInOnAnAccountCreatedThreeMinutesAgoGoesHome() async {
        let harness = makeHarness()
        let ada = user(createdMinutesAgo: 3)

        await signInWithACode(harness, entry: .signIn, as: ada)

        #expect(await eventually { harness.authStore.state == .signedIn(ada) })
        #expect(harness.submissions.value.isEmpty)
    }

    @Test func finishingThatOnboardingSendsTheAnswersAndGoesOnAtOnce() async {
        let harness = makeHarness()
        let ada = user(createdMinutesAgo: 1)
        await signInWithACode(harness, entry: .signIn, as: ada)
        #expect(await eventually { harness.authStore.state == .onboarding(ada) })

        harness.authStore.finishOnboarding()

        #expect(harness.authStore.state == .paywall(ada))
        #expect(await eventually { harness.submissions.value.count == 1 })
        harness.pendingRequest.wakeAll()
    }
}
