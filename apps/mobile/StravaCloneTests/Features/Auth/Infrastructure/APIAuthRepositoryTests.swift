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

    /// Better Auth's emailOTP send route (ADR-035 §2): `type` is always "sign-in", which also
    /// signs up.
    @Test func sendSignInCodePostsTheEmailWithTheSignInType() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/email-otp/send-verification-otp")
            let json = try request.jsonBody()
            #expect(json == ["email": "a@b.com", "type": "sign-in"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true}"#.utf8))
        }

        try await repository.sendSignInCode(email: "a@b.com")
    }

    @Test func signInWithACodeSendsTheNameAndStoresTheBearerToken() async throws {
        let (repository, authSession) = makeRepository()
        authSession.clear()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/auth/sign-in/email-otp")
            let json = try request.jsonBody()
            #expect(json == ["email": "a@b.com", "otp": "123456", "name": "Ada Lovelace"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["set-auth-token": "token-123", "Content-Type": "application/json"]
            )!
            let body = #"{"token":"raw","user":{"id":"u1","email":"a@b.com","name":"Ada Lovelace"}}"#
            return (response, Data(body.utf8))
        }

        let user = try await repository.signIn(email: "a@b.com", code: "123456", name: "Ada Lovelace")

        #expect(user == AuthUser(id: "u1", email: "a@b.com", name: "Ada Lovelace"))
        #expect(authSession.token() == "token-123")
    }

    /// "Se connecter" may have just created the account (ADR-035 §1): the response's
    /// `user.createdAt` tells.
    @Test func signInReadsWhenTheAccountWasCreated() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"token":"raw","user":{"id":"u1","email":"a@b.com","name":"Ada","createdAt":"2026-11-02T08:15:30.250Z"}}"#
            return (response, Data(body.utf8))
        }

        let user = try await repository.signIn(email: "a@b.com", code: "123456", name: nil)

        #expect(user.createdAt == Date(timeIntervalSince1970: 1_793_607_330.25))
    }

    /// Better Auth only uses `name` when the code creates the account: none is sent unless given.
    @Test func signInWithACodeLeavesTheNameOutWhenThereIsNone() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let json = try request.jsonBody()
            #expect(json == ["email": "a@b.com", "otp": "123456"])
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["set-auth-token": "token-1"]
            )!
            return (response, Data(#"{"user":{"id":"u1","email":"a@b.com","name":""}}"#.utf8))
        }

        _ = try await repository.signIn(email: "a@b.com", code: "123456", name: nil)
    }

    /// Better Auth's emailOTP answers (`dist/plugins/email-otp/error-codes.mjs`), and its rate limit.
    @Test(arguments: [
        (400, #"{"code":"INVALID_OTP","message":"Invalid OTP"}"#, AuthError.invalidCode),
        (400, #"{"code":"OTP_EXPIRED","message":"OTP expired"}"#, AuthError.codeExpired),
        (403, #"{"code":"TOO_MANY_ATTEMPTS","message":"Too many attempts"}"#, AuthError.tooManyAttempts),
        (429, "", AuthError.rateLimited),
        (400, #"{"code":"INVALID_EMAIL","message":"Invalid email"}"#, AuthError.server(message: "Invalid email")),
    ])
    func signInWithACodeMapsTheServerErrors(status: Int, body: String, expected: AuthError) async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        await #expect(throws: expected) {
            try await repository.signIn(email: "a@b.com", code: "000001", name: nil)
        }
    }

    /// A banned athlete's sign-in (ADR-038 §6): `403 BANNED_USER` with the Ban's end, its reason
    /// and the contact address, by Sign-in code or Google.
    @Test(arguments: [
        (
            #"{"code":"BANNED_USER","message":"Votre compte est suspendu jusqu'au 11 novembre 2026 à 14:30.","bannedUntil":"2026-11-11T13:30:00.000Z","banReason":"Propos haineux","contactEmail":"contact@nervo.app"}"#,
            AccountSuspension(
                until: Date(timeIntervalSince1970: 1_794_403_800), reason: "Propos haineux", contactEmail: "contact@nervo.app"
            )
        ),
        (
            #"{"code":"BANNED_USER","message":"Votre compte est suspendu définitivement.","bannedUntil":null,"banReason":null,"contactEmail":null}"#,
            AccountSuspension(until: nil, reason: nil, contactEmail: nil)
        ),
    ])
    func aBannedAccountsSignInIsSuspended(body: String, expected: AccountSuspension) async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        await #expect(throws: AuthError.accountSuspended(expected)) {
            try await repository.signIn(email: "a@b.com", code: "000000", name: nil)
        }
        await #expect(throws: AuthError.accountSuspended(expected)) {
            try await repository.signInWithGoogle(idToken: "raw-google-id-token")
        }
    }

    @Test func sendSignInCodeRateLimitedMapsToRateLimited() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: AuthError.rateLimited) { try await repository.sendSignInCode(email: "a@b.com") }
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

    @Test func currentUserWithoutASessionIsNotSignedIn() async throws {
        let (repository, authSession) = makeRepository()
        defer { authSession.clear() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
            return (response, Data("null".utf8))
        }

        await #expect(throws: AuthError.notSignedIn) { try await repository.currentUser() }
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

    /// The request's JSON object body, string values only (the auth bodies have no others).
    func jsonBody() throws -> [String: String] {
        let body = try #require(httpBodyStreamAsData() ?? httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    }
}
