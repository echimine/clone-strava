import Testing
@testable import StravaClone

@MainActor
struct AuthStoreTests {
    private func makeStore() -> (AuthStore, FakeAuthRepository) {
        let repository = FakeAuthRepository()
        let service = AuthService(repository: repository, googleAuthProvider: FakeGoogleAuthProvider())
        return (AuthStore(service: service), repository)
    }

    @Test func restoreSessionWithNoValidTokenGoesToSignedOut() async {
        let (store, repository) = makeStore()
        repository.currentUserHandler = { () throws(AuthError) in throw AuthError.notSignedIn }

        await store.restoreSession()

        #expect(store.state == .signedOut)
    }

    @Test func restoreSessionWithValidTokenGoesToSignedIn() async {
        let (store, repository) = makeStore()
        let user = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.currentUserHandler = { user }

        await store.restoreSession()

        #expect(store.state == .signedIn(user))
    }

    @Test func signOutReturnsToSignedOut() async {
        let (store, repository) = makeStore()
        repository.currentUserHandler = { AuthUser(id: "1", email: "a@b.com", name: "Ada") }
        await store.restoreSession()

        repository.signOutHandler = {}
        await store.signOut()

        #expect(store.state == .signedOut)
        #expect(store.welcomeNotice == nil)
    }

    @Test func aDeletedAccountSignsOutLocallyAndTheWelcomeSaysSo() async {
        let (store, repository) = makeStore()
        repository.currentUserHandler = { AuthUser(id: "1", email: "a@b.com", name: "Ada") }
        await store.restoreSession()
        let signedOut = Locked(false)
        repository.signOutHandler = { signedOut.value = true }

        await store.accountDeleted()

        #expect(store.state == .signedOut)
        #expect(signedOut.value)
        #expect(store.welcomeNotice == "Compte supprimé")
    }
}
