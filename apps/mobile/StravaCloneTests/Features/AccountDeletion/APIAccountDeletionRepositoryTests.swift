import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIModerationRepositoryTests`: suites run in parallel.
private final class AccountDeletionURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[(URLRequest, Data?)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append((request, request.httpBody ?? request.httpBodyStream.map(Self.read)))
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite(.serialized)
struct APIAccountDeletionRepositoryTests {
    private func makeRepository() -> APIAccountDeletionRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeletionURLProtocolStub.self]
        let authSession = AuthSession(service: "test.account-deletion.\(UUID())")
        authSession.clear()
        AccountDeletionURLProtocolStub.requests.value = []
        return APIAccountDeletionRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        AccountDeletionURLProtocolStub.handler.value = { _ in (status, body) }
    }

    @Test func thePreviewTellsWhetherAppleKeepsBilling() async throws {
        let repository = makeRepository()
        respond(200, #"{ "appStoreBilled": true }"#)

        #expect(try await repository.appStoreBilled())
        let (request, _) = try #require(AccountDeletionURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/me/account-deletion")
    }

    @Test func theCodeIsAskedForThenSentWithTheDeletion() async throws {
        let repository = makeRepository()
        respond(204, "")

        try await repository.sendCode()
        try await repository.deleteAccount(code: "000000")

        let requests = AccountDeletionURLProtocolStub.requests.value
        #expect(requests.map(\.0.httpMethod) == ["POST", "POST"])
        #expect(requests.map(\.0.url?.path) == ["/v1/me/account-deletion/code", "/v1/me/account-deletion"])
        let body = try #require(requests.last?.1)
        #expect(try JSONSerialization.jsonObject(with: body) as? [String: String] == ["code": "000000"])
    }

    @Test func theServersRefusalsHaveTheirErrors() async {
        let repository = makeRepository()
        respond(403, #"{ "error": { "code": "admin_cannot_delete_account", "message": "No" } }"#)
        await #expect(throws: AccountDeletionError.administrator) { try await repository.sendCode() }

        respond(400, #"{ "error": { "code": "invalid_code", "message": "No" } }"#)
        await #expect(throws: AccountDeletionError.invalidCode) { try await repository.deleteAccount(code: "1") }

        respond(400, #"{ "error": { "code": "code_expired", "message": "No" } }"#)
        await #expect(throws: AccountDeletionError.expiredCode) { try await repository.deleteAccount(code: "1") }

        respond(400, #"{ "error": { "code": "too_many_attempts", "message": "No" } }"#)
        await #expect(throws: AccountDeletionError.expiredCode) { try await repository.deleteAccount(code: "1") }
    }
}
