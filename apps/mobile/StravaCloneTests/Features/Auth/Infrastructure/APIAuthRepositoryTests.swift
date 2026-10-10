import Foundation
import Testing
@testable import StravaClone

/// Serialized: every test scripts the shared `URLProtocolStub.handler`.
@Suite(.serialized)
struct APIAuthRepositoryTests {
    private func makeRepository() -> (APIAuthRepository, AuthSession) {
        // Unique Keychain service per test run so tests never read/pollute the real
        // simulator Keychain, and never see state left by a previous run.
        let authSession = AuthSession(service: "test.auth.\(UUID())")
        let apiClient = APIClient(
            baseURL: URL(string: "https://example.invalid")!,
            session: URLProtocolStub.makeSession(),
            authSession: authSession
        )
        return (APIAuthRepository(apiClient: apiClient, authSession: authSession), authSession)
    }

    @Test func signInStoresBearerTokenFromResponseHeader() async throws {
        let (repository, authSession) = makeRepository()
        authSession.clear()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["set-auth-token": "token-123", "Content-Type": "application/json"]
            )!
            let body = #"{"user":{"id":"u1","email":"a@b.com","name":"Ada"}}"#.data(using: .utf8)!
            return (response, body)
        }

        let user = try await repository.signIn(email: "a@b.com", password: "secret")

        #expect(user == AuthUser(id: "u1", email: "a@b.com", name: "Ada"))
        #expect(authSession.token() == "token-123")
    }

    @Test func signInWithWrongCredentialsMapsToInvalidCredentials() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: AuthError.invalidCredentials) {
            try await repository.signIn(email: "a@b.com", password: "wrong")
        }
    }

    @Test func signInRateLimitedMapsToRateLimited() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: AuthError.rateLimited) {
            try await repository.signIn(email: "a@b.com", password: "secret")
        }
    }

    @Test func signUpWithExistingEmailMapsToEmailAlreadyInUse() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            let body = #"{"code":"USER_ALREADY_EXISTS","message":"User already exists."}"#.data(using: .utf8)!
            return (response, body)
        }

        await #expect(throws: AuthError.emailAlreadyInUse) {
            try await repository.signUp(email: "a@b.com", password: "secret", name: "Ada")
        }
    }

    @Test func signUpWithUnmappedServerErrorSurfacesItsMessage() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let body = #"{"code":"PASSWORD_TOO_SHORT","message":"Password too short"}"#.data(using: .utf8)!
            return (response, body)
        }

        await #expect(throws: AuthError.server(message: "Password too short")) {
            try await repository.signUp(email: "a@b.com", password: "x", name: "Ada")
        }
    }

    @Test func signInWithGoogleSendsProviderAndIdToken() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let body = try #require(request.httpBodyStreamAsData() ?? request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["provider"] as? String == "google")
            let idToken = json?["idToken"] as? [String: Any]
            #expect(idToken?["token"] as? String == "raw-google-id-token")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["set-auth-token": "token-456"]
            )!
            let responseBody = #"{"user":{"id":"u2","email":"g@b.com","name":"Gina"}}"#.data(using: .utf8)!
            return (response, responseBody)
        }

        let user = try await repository.signInWithGoogle(idToken: "raw-google-id-token")

        #expect(user == AuthUser(id: "u2", email: "g@b.com", name: "Gina"))
        #expect(authSession.token() == "token-456")
    }

    /// Launch-time check over `get-session`, like the refresh after a `401` (ADR-022).
    @Test func currentUserReadsTheSessionAndKeepsARenewedToken() async throws {
        let (repository, authSession) = makeRepository()
        authSession.clear()
        authSession.store(token: "old-token")
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            #expect(request.url?.path == "/api/auth/get-session")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["set-auth-token": "new-token"]
            )!
            let body = #"{"session":{"id":"s"},"user":{"id":"u3","email":"c@b.com","name":"Cy"}}"#.data(using: .utf8)!
            return (response, body)
        }

        let user = try await repository.currentUser()

        #expect(user == AuthUser(id: "u3", email: "c@b.com", name: "Cy"))
        #expect(authSession.token() == "new-token")
    }

    @Test func currentUserWithoutASessionIsInvalidCredentials() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
            return (response, Data("null".utf8))
        }

        await #expect(throws: AuthError.invalidCredentials) { try await repository.currentUser() }
    }
}

private extension URLRequest {
    /// `URLProtocol` may expose the body via `httpBodyStream` rather than `httpBody`
    /// depending on the session configuration; this normalizes both.
    func httpBodyStreamAsData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
