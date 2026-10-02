import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub: `URLProtocolStub`'s handler is global and other suites run in
/// parallel, so this suite keeps its handler to itself and runs serialized.
private final class ImportURLProtocolStub: URLProtocol, @unchecked Sendable {
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

@Suite(.serialized)
struct APIActivityImportRepositoryTests {
    private let id = UUID(uuidString: "8C1B5D0A-1F2E-4C3D-9A8B-7C6D5E4F3A2B")!

    private func makeRepository() -> (APIActivityImportRepository, AuthSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImportURLProtocolStub.self]
        let authSession = AuthSession(service: "test.import.\(UUID())")
        authSession.clear()
        ImportURLProtocolStub.requests.value = []
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: configuration),
            authSession: authSession
        )
        return (APIActivityImportRepository(apiClient: apiClient), authSession)
    }

    private func importJSON(status: String) -> String {
        #"{"id":"8c1b5d0a-1f2e-4c3d-9a8b-7c6d5e4f3a2b","format":"gpx","fileName":"run.gpx","status":"\#(status)","createdAt":"2026-10-02T10:00:00.000Z"}"#
    }

    @Test func createSendsTheOverridesAndDecodesTheUploadURL() async throws {
        let (repository, _) = makeRepository()
        let json = #"{"import":\#(importJSON(status: "pending")),"upload":{"uploadUrl":"https://bucket.test/imports/u/x/source.gpx?sig=1","expiresAt":"2026-10-02T10:15:00.000Z"}}"#
        ImportURLProtocolStub.handler.value = { _ in (201, Data(json.utf8)) }

        let (created, upload) = try await repository.create(
            id: id,
            file: .fixture,
            options: ImportOptions(sport: .ride, title: nil, visibility: .onlyMe)
        )

        #expect(created.status == .pending)
        #expect(upload?.url.absoluteString == "https://bucket.test/imports/u/x/source.gpx?sig=1")
        let request = try #require(ImportURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/activity-imports")
        let body = try JSONSerialization.jsonObject(with: try #require(request.bodyData)) as? [String: Any]
        #expect(body?["sportTypeCode"] as? String == "ride")
        #expect(body?["visibility"] as? String == "private")
        #expect(body?["format"] as? String == "gpx")
        #expect(body?["title"] == nil)
    }

    @Test func mapsServerErrorCodesAndRateLimit() async {
        let (repository, _) = makeRepository()
        ImportURLProtocolStub.handler.value = { _ in (409, Data(#"{"error":{"code":"file_missing","message":"x"}}"#.utf8)) }
        await #expect(throws: ImportError.server(code: "file_missing")) {
            try await repository.complete(id: id)
        }

        ImportURLProtocolStub.handler.value = { _ in (429, Data()) }
        await #expect(throws: ImportError.rateLimited) {
            try await repository.fetch(id: id)
        }
    }

    @Test func uploadPutsTheFileWithoutAuthorizationAndMaps403ToExpired() async throws {
        let (repository, authSession) = makeRepository()
        authSession.store(token: "secret-token")
        defer { authSession.clear() }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).gpx")
        try Data("<gpx/>".utf8).write(to: file)
        let importFile = ImportFile(localURL: file, fileName: "run.gpx", format: .gpx, sizeBytes: 6)
        let target = UploadTarget(url: URL(string: "https://bucket.test/put")!, expiresAt: .now)

        ImportURLProtocolStub.handler.value = { _ in (200, Data()) }
        try await repository.upload(file: importFile, to: target)
        let request = try #require(ImportURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        ImportURLProtocolStub.handler.value = { _ in (403, Data()) }
        await #expect(throws: ImportError.uploadURLExpired) {
            try await repository.upload(file: importFile, to: target)
        }
    }
}

private extension URLRequest {
    /// `URLProtocol` receives bodies as a stream, not `httpBody`.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
