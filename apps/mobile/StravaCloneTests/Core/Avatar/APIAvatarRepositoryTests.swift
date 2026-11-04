import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIProfileRepositoryTests`: suites run in parallel.
private final class AvatarURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[(request: URLRequest, body: Data?)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append((request, request.avatarBody))
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// `URLSession` hands the protocol a stream rather than `httpBody`.
    var avatarBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// My Avatar over the API (ADR-037 §2, routes of #171): ask for an upload URL, `PUT` the JPEG
/// to the bucket with the signed headers, then store it.
@Suite(.serialized)
struct APIAvatarRepositoryTests {
    private let avatarId = "6f1c2a9e-8b0d-4c3e-9a51-2d7e4f6b8c10"
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"
    private let uploadURL = "https://bucket.test/test/avatars/me/6f1c2a9e.jpg?X-Amz-Signature=put"
    private let avatarURL = "https://bucket.test/test/avatars/me/6f1c2a9e.jpg?X-Amz-Signature=get"
    private let jpeg = Data(repeating: 0xAB, count: 2_048)

    private func makeRepository() -> APIAvatarRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarURLProtocolStub.self]
        let authSession = AuthSession(service: "test.avatar.\(UUID())")
        authSession.clear()
        authSession.store(token: "session-token")
        AvatarURLProtocolStub.requests.value = []
        return APIAvatarRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    /// The three answers of a successful upload; `bucketStatus` for the pre-signed `PUT`.
    private func respondToAnUpload(bucketStatus: Int = 200, setStatus: Int = 200, setBody: String? = nil) {
        let ticket = Data(#"{ "avatarId": "\#(avatarId)", "uploadUrl": "\#(uploadURL)", "expiresAt": "2026-11-03T21:15:00.000Z" }"#.utf8)
        let stored = Data((setBody ?? #"{ "athlete": { "id": "\#(athleteId)", "displayName": "Camille Martin", "avatarUrl": "\#(avatarURL)" } }"#).utf8)
        AvatarURLProtocolStub.handler.value = { request in
            switch (request.httpMethod, request.url?.host, request.url?.path) {
            case ("POST", "api.test", "/v1/me/avatar/upload-url"): (201, ticket)
            case ("PUT", "bucket.test", _): (bucketStatus, Data())
            case ("PUT", "api.test", "/v1/me/avatar"): (setStatus, stored)
            default: (500, Data())
            }
        }
    }

    private func json(_ body: Data?) throws -> NSDictionary? {
        try JSONSerialization.jsonObject(with: #require(body)) as? NSDictionary
    }

    @Test func anUploadAsksForAURLSendsTheJPEGThenStoresIt() async throws {
        let repository = makeRepository()
        respondToAnUpload()

        let url = try await repository.upload(jpeg)

        let requests = AvatarURLProtocolStub.requests.value
        #expect(requests.count == 3)
        let ask = requests[0]
        #expect(ask.request.url?.absoluteString == "https://api.test/v1/me/avatar/upload-url")
        #expect(try json(ask.body) == ["sizeBytes": 2_048])

        let put = requests[1]
        #expect(put.request.httpMethod == "PUT")
        #expect(put.request.url?.absoluteString == uploadURL)
        #expect(put.request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(put.request.value(forHTTPHeaderField: "Content-Length") == "2048")
        #expect(put.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(put.body == jpeg)

        let store = requests[2]
        #expect(store.request.url?.absoluteString == "https://api.test/v1/me/avatar")
        #expect(try json(store.body) == ["avatarId": avatarId])
        #expect(url == URL(string: avatarURL))
    }

    @Test func aBucketRefusalIsARejectionAndNothingIsStored() async {
        let repository = makeRepository()
        respondToAnUpload(bucketStatus: 403)

        await #expect(throws: AvatarError.rejected(code: nil)) {
            _ = try await repository.upload(jpeg)
        }
        #expect(AvatarURLProtocolStub.requests.value.count == 2)
    }

    @Test func aMissingObjectKeepsTheAPIsCode() async {
        let repository = makeRepository()
        respondToAnUpload(setStatus: 409, setBody: #"{ "error": { "code": "avatar_missing", "message": "x" } }"#)

        await #expect(throws: AvatarError.rejected(code: "avatar_missing")) {
            _ = try await repository.upload(jpeg)
        }
    }

    @Test func removingDeletesMyAvatar() async throws {
        let repository = makeRepository()
        AvatarURLProtocolStub.handler.value = { _ in (204, Data()) }

        try await repository.remove()

        let request = try #require(AvatarURLProtocolStub.requests.value.last?.request)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.test/v1/me/avatar")
    }

    @Test func aServerErrorOnRemovalIsAServerFailure() async {
        let repository = makeRepository()
        AvatarURLProtocolStub.handler.value = { _ in (500, Data()) }

        await #expect(throws: AvatarError.server) {
            try await repository.remove()
        }
    }
}
