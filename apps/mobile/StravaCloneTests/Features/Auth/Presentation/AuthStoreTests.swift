import Testing
@testable import StravaClone

@MainActor
struct AuthStoreTests {
    private func makeStore() -> (AuthStore, FakeAuthRepository, FakeGoogleAuthProvider) {
        let repository = FakeAuthRepository()
        let googleAuthProvider = FakeGoogleAuthProvider()
        let service = AuthService(repository: repository, googleAuthProvider: googleAuthProvider)
        return (AuthStore(service: service), repository, googleAuthProvider)
    }

    @Test func signInSuccessTransitionsToSignedIn() async {
        let (store, repository, _) = makeStore()
        let user = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.signInHandler = { _, _ in user }

        await store.signIn(email: "a@b.com", password: "secret")

        #expect(store.state == .signedIn(user))
        #expect(store.formError == nil)
        #expect(store.isSubmitting == false)
    }

    @Test func signInFailurePopulatesFormError() async {
        let (store, repository, _) = makeStore()
        repository.signInHandler = { (_: String, _: String) throws(AuthError) in throw AuthError.invalidCredentials }

        await store.signIn(email: "a@b.com", password: "wrong")

        #expect(store.formError == .invalidCredentials)
        #expect(store.isSubmitting == false)
        if case .signedIn = store.state { Issue.record("should not be signed in") }
    }

    @Test func rateLimitedMapsToDedicatedFormError() async {
        let (store, repository, _) = makeStore()
        repository.signUpHandler = { (_: String, _: String, _: String) throws(AuthError) in throw AuthError.rateLimited }

        await store.signUp(email: "a@b.com", password: "secret", name: "Ada")

        #expect(store.formError == .rateLimited)
    }

    @Test func cancelledGoogleSignInIsNotSurfacedAsAnError() async {
        let (store, _, googleAuthProvider) = makeStore()
        googleAuthProvider.signInHandler = { () throws(AuthError) in throw AuthError.googleSignInCancelled }

        await store.signInWithGoogle()

        #expect(store.formError == nil)
    }

    @Test func restoreSessionWithNoValidTokenGoesToSignedOut() async {
        let (store, repository, _) = makeStore()
        repository.currentUserHandler = { () throws(AuthError) in throw AuthError.invalidCredentials }

        await store.restoreSession()

        #expect(store.state == .signedOut)
    }

    @Test func restoreSessionWithValidTokenGoesToSignedIn() async {
        let (store, repository, _) = makeStore()
        let user = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.currentUserHandler = { user }

        await store.restoreSession()

        #expect(store.state == .signedIn(user))
    }

    @Test func signOutReturnsToSignedOut() async {
        let (store, repository, _) = makeStore()
        repository.signInHandler = { _, _ in AuthUser(id: "1", email: "a@b.com", name: "Ada") }
        await store.signIn(email: "a@b.com", password: "secret")

        repository.signOutHandler = {}
        await store.signOut()

        #expect(store.state == .signedOut)
    }
}
