import Testing
@testable import StravaClone

struct AuthServiceTests {
    private func makeService() -> (AuthService, FakeAuthRepository, FakeGoogleAuthProvider) {
        let repository = FakeAuthRepository()
        let googleAuthProvider = FakeGoogleAuthProvider()
        let service = AuthService(repository: repository, googleAuthProvider: googleAuthProvider)
        return (service, repository, googleAuthProvider)
    }

    @Test func signUpUpdatesCurrentUser() async throws {
        let (service, repository, _) = makeService()
        let expected = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.signUpHandler = { _, _, _ in expected }

        let user = try await service.signUp(email: "a@b.com", password: "secret", name: "Ada")

        #expect(user == expected)
        #expect(await service.currentUser == expected)
    }

    @Test func signInUpdatesCurrentUser() async throws {
        let (service, repository, _) = makeService()
        let expected = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.signInHandler = { _, _ in expected }

        let user = try await service.signIn(email: "a@b.com", password: "secret")

        #expect(user == expected)
        #expect(await service.currentUser == expected)
    }

    @Test func signInWithGoogleChainsProviderThenRepository() async throws {
        let (service, repository, googleAuthProvider) = makeService()
        let expected = AuthUser(id: "2", email: "g@b.com", name: "Gina")
        googleAuthProvider.signInHandler = { "raw-id-token" }
        repository.signInWithGoogleHandler = { idToken in
            #expect(idToken == "raw-id-token")
            return expected
        }

        let user = try await service.signInWithGoogle()

        #expect(user == expected)
        #expect(await service.currentUser == expected)
    }

    @Test func signOutClearsCurrentUser() async throws {
        let (service, repository, _) = makeService()
        repository.signInHandler = { _, _ in AuthUser(id: "1", email: "a@b.com", name: "Ada") }
        _ = try await service.signIn(email: "a@b.com", password: "secret")

        let signOutCalled = Locked(false)
        repository.signOutHandler = { signOutCalled.value = true }
        await service.signOut()

        #expect(signOutCalled.value)
        #expect(await service.currentUser == nil)
    }

    @Test func restoreSessionReturnsNilWhenRepositoryThrows() async throws {
        let (service, repository, _) = makeService()
        repository.currentUserHandler = { () throws(AuthError) in throw AuthError.invalidCredentials }

        let user = await service.restoreSession()

        #expect(user == nil)
        #expect(await service.currentUser == nil)
    }

    @Test func restoreSessionReturnsUserWhenValid() async throws {
        let (service, repository, _) = makeService()
        let expected = AuthUser(id: "1", email: "a@b.com", name: "Ada")
        repository.currentUserHandler = { expected }

        let user = await service.restoreSession()

        #expect(user == expected)
        #expect(await service.currentUser == expected)
    }
}
