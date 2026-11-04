import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFollowRepositoryTests`: suites run in parallel.
private final class ModerationURLProtocolStub: URLProtocol, @unchecked Sendable {
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
struct APIModerationRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"
    private let reportId = "7c1e2f0e-5b1c-4f3e-9d43-3c2a1b0e9f02"

    private var author: ActivityAuthor { ActivityAuthor(id: athleteId, displayName: "Léa Martin", avatarURL: nil) }

    private func makeRepository() -> APIModerationRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModerationURLProtocolStub.self]
        let authSession = AuthSession(service: "test.moderation.\(UUID())")
        authSession.clear()
        ModerationURLProtocolStub.requests.value = []
        return APIModerationRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        ModerationURLProtocolStub.handler.value = { _ in (status, body) }
    }

    @Test func aReportPostsTheTargetAndReason() async throws {
        let repository = makeRepository()
        respond(201, #"{ "id": "\#(reportId)" }"#)

        let outcome = try await repository.report(.athlete(author), reason: .sexualOrViolent, note: "Photo")

        let (request, body) = try #require(ModerationURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/reports")
        let data = try #require(body)
        let sent = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(sent == ["targetType": "athlete", "targetId": athleteId, "reason": "sexual_or_violent", "note": "Photo"])
        #expect(outcome == .reported)
    }

    @Test func a200IsAlreadyReported() async throws {
        let repository = makeRepository()
        respond(200, #"{ "id": "\#(reportId)" }"#)

        #expect(try await repository.report(.athlete(author), reason: .spam, note: nil) == .alreadyReported)
    }

    @Test func theLimitAndAMissingTargetHaveTheirErrors() async {
        let repository = makeRepository()
        respond(429, #"{ "error": { "code": "report_limit_reached", "message": "No" } }"#)
        await #expect(throws: ModerationError.rateLimited) {
            try await repository.report(.athlete(author), reason: .spam, note: nil)
        }
        respond(404, #"{ "error": { "code": "comment_not_found", "message": "No" } }"#)
        await #expect(throws: ModerationError.notFound) {
            try await repository.report(.comment("c1", by: author), reason: .spam, note: nil)
        }
    }

    @Test func blockingAndUnblockingPutAndDeleteTheBlock() async throws {
        let repository = makeRepository()
        respond(204, "")

        try await repository.block(athleteId)
        try await repository.unblock(athleteId)

        let requests = ModerationURLProtocolStub.requests.value.map(\.0)
        #expect(requests.map(\.httpMethod) == ["PUT", "DELETE"])
        #expect(requests.map(\.url?.path) == ["/v1/me/blocks/\(athleteId)", "/v1/me/blocks/\(athleteId)"])
    }

    @Test func theBlockedListDecodesEachAthlete() async throws {
        let repository = makeRepository()
        respond(200, #"""
        { "items": [ { "athlete": { "id": "\#(athleteId)", "displayName": "Léa Martin", "avatarUrl": null },
                       "blockedAt": "2026-11-04T10:00:00.000Z" } ] }
        """#)

        let athletes = try await repository.blockedAthletes()

        #expect(athletes.map(\.athlete) == [author])
        #expect(athletes.first?.blockedAt == ISO8601DateFormatter().date(from: "2026-11-04T10:00:00Z"))
    }
}
