import Foundation
import Testing
@testable import StravaClone

/// The notification priming screen (ADR-035 §7): after the Paywall of the Onboarding path, only
/// while iOS has not asked yet; "Activer les notifications" opens the system prompt, "Plus tard"
/// does not; both lead home.
@MainActor
struct AuthStoreNotificationPrimerTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_793_607_330)

    private let repository = FakeAuthRepository()
    private let google = FakeGoogleAuthProvider()
    private let ada = AuthUser(id: "u1", email: "a@b.com", name: "Ada Lovelace", createdAt: now)

    private func makeAuthStore(_ permission: FakeNotificationPermission) -> AuthStore {
        AuthStore(
            service: AuthService(repository: repository, googleAuthProvider: google),
            sleep: ManualSleeper().sleep,
            notificationPermission: permission,
            now: { Self.now }
        )
    }

    /// Signed in at the end of the Onboarding, so on the Paywall.
    private func onThePaywall(_ permission: FakeNotificationPermission) async -> AuthStore {
        let authStore = makeAuthStore(permission)
        repository.sendSignInCodeHandler = { _ in }
        repository.signInHandler = { [ada] _, _, _ in ada }
        let signIn = authStore.makeSignInStore(entry: .onboarding(name: "Ada Lovelace"))
        signIn.email = "a@b.com"
        await signIn.sendCode()
        signIn.enterCode("123456")
        _ = await eventually { authStore.state == .paywall(ada) }
        return authStore
    }

    @Test func leavingThePaywallShowsThePrimerWhileIOSHasNotAskedYet() async {
        let permission = FakeNotificationPermission(status: .notDetermined)
        let authStore = await onThePaywall(permission)

        await authStore.finishPaywall()

        #expect(authStore.state == .notificationPrimer(ada))
        #expect(permission.requestCount == 0)
    }

    /// Already granted or denied, for example a second account on the same phone: skipped
    /// silently.
    @Test(arguments: [NotificationAuthorization.granted, .denied])
    func leavingThePaywallGoesHomeWhenThePermissionIsSettled(status: NotificationAuthorization) async {
        let permission = FakeNotificationPermission(status: status)
        let authStore = await onThePaywall(permission)

        await authStore.finishPaywall()

        #expect(authStore.state == .signedIn(ada))
        #expect(permission.requestCount == 0)
    }

    @Test(arguments: [true, false])
    func enablingNotificationsAsksIOSThenGoesHome(allowed: Bool) async {
        let permission = FakeNotificationPermission(status: .notDetermined, answer: allowed)
        let authStore = await onThePaywall(permission)
        await authStore.finishPaywall()

        await authStore.enableNotifications()

        #expect(permission.requestCount == 1)
        #expect(authStore.state == .signedIn(ada))
    }

    @Test func plusTardGoesHomeWithoutAskingIOS() async {
        let permission = FakeNotificationPermission(status: .notDetermined)
        let authStore = await onThePaywall(permission)
        await authStore.finishPaywall()

        authStore.deferNotifications()

        #expect(authStore.state == .signedIn(ada))
        #expect(permission.requestCount == 0)
    }

    /// "Se connecter" on an existing account never sees the Paywall, so never the primer.
    @Test func seConnecterOnAnExistingAccountNeverShowsThePrimer() async {
        let permission = FakeNotificationPermission(status: .notDetermined)
        let authStore = makeAuthStore(permission)
        let lea = AuthUser(id: "u2", email: "l@b.com", name: "Léa", createdAt: Self.now.addingTimeInterval(-3_600))
        repository.sendSignInCodeHandler = { _ in }
        repository.signInHandler = { _, _, _ in lea }
        let signIn = authStore.makeSignInStore(entry: .signIn)
        signIn.email = "l@b.com"
        await signIn.sendCode()
        signIn.enterCode("123456")

        #expect(await eventually { authStore.state == .signedIn(lea) })
        await authStore.finishPaywall()
        #expect(authStore.state == .signedIn(lea))
    }

    /// The app killed on the primer: the next launch goes home, the primer is not resumed.
    @Test func aRestoredSessionGoesHomeWithoutThePrimer() async {
        let permission = FakeNotificationPermission(status: .notDetermined)
        let authStore = makeAuthStore(permission)
        repository.currentUserHandler = { [ada] in ada }

        await authStore.restoreSession()

        #expect(authStore.state == .signedIn(ada))
    }
}
