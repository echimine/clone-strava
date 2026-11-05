import Foundation
import Testing
@testable import StravaClone

/// RevenueCat's subscriber follows the session (ADR-014): `logIn` with our user id as soon as a
/// session exists (after the code, at launch), `logOut` at sign-out.
@MainActor
struct AuthStoreSubscriberIdentityTests {
    private let ada = AuthUser(id: "u1", email: "a@b.com", name: "Ada")
    private let repository = FakeAuthRepository()
    private let identity = FakeSubscriberIdentity()

    private func makeAuthStore() -> AuthStore {
        let service = AuthService(repository: repository, googleAuthProvider: FakeGoogleAuthProvider())
        return AuthStore(service: service, subscriberIdentity: identity, sleep: ManualSleeper().sleep)
    }

    @Test func aLaunchWithASessionLogsTheSubscriberIn() async {
        repository.currentUserHandler = { [ada] in ada }
        let authStore = makeAuthStore()

        await authStore.restoreSession()

        #expect(identity.calls == [.logIn(userId: "u1")])
    }

    @Test func signingInWithACodeLogsTheSubscriberIn() async {
        repository.sendSignInCodeHandler = { _ in }
        repository.signInHandler = { [ada] _, _, _ in ada }
        let authStore = makeAuthStore()
        let signIn = authStore.makeSignInStore()
        signIn.email = "a@b.com"
        await signIn.sendCode()

        signIn.enterCode("123456")

        #expect(await eventually { authStore.state == .signedIn(ada) })
        #expect(identity.calls == [.logIn(userId: "u1")])
    }

    @Test func signingOutLogsTheSubscriberOut() async {
        repository.currentUserHandler = { [ada] in ada }
        let authStore = makeAuthStore()
        await authStore.restoreSession()

        await authStore.signOut()

        #expect(identity.calls == [.logIn(userId: "u1"), .logOut])
    }
}
