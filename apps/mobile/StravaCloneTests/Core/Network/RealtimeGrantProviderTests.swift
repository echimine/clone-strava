import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIActivityKudosRepositoryTests`: suites run in parallel.
private final class GrantURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `POST /v1/realtime/grants` (ADR-034 §5) through the generated OpenAPI types (ADR-026).
@Suite(.serialized)
struct RealtimeGrantProviderTests {
    private func makeProvider() -> RealtimeGrantProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrantURLProtocolStub.self]
        let authSession = AuthSession(service: "test.realtimeGrant.\(UUID())")
        authSession.clear()
        GrantURLProtocolStub.requests.value = []
        return RealtimeGrantProvider(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    @Test func asksAGrantForTheTopic() async throws {
        let provider = makeProvider()
        GrantURLProtocolStub.handler.value = { _ in (200, Data(#"{"grant":"jwt.grant","expiresInS":60}"#.utf8)) }
        let topic = realtimeActivityTopic(ActivityID(UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!))

        let grant = try await provider.grant(topic: topic)

        #expect(grant == "jwt.grant")
        let request = try #require(GrantURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/realtime/grants")
        let body = try #require(request.httpBody ?? request.httpBodyStream.map(Self.read))
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        // Lowercase, as the API stores the id: the gateway compares topics exactly.
        #expect(sent == ["topic": "activity:7c9e6679-7425-40de-944b-e07fc1f90ae7"])
    }

    @Test func aRefusedGrantIsAnError() async {
        let provider = makeProvider()
        GrantURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"activity_not_found","message":"Not found"}}"#.utf8))
        }

        await #expect(throws: APIError.self) {
            try await provider.grant(topic: "activity:7c9e6679-7425-40de-944b-e07fc1f90ae7")
        }
    }

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
