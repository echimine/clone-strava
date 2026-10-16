import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class DetailURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])
    /// Request bodies, read from `httpBodyStream` (`URLProtocol` does not keep `httpBody`).
    static let bodies = Locked<[Data]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        Self.bodies.value.append(request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data())
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
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// `GET /v1/activities/:id` (ADR-033 §2) through the generated `ActivityDetailDto_Output`.
@Suite(.serialized)
struct APIActivityDetailRepositoryTests {
    private let activityId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private var id: ActivityID { ActivityID(UUID(uuidString: activityId)!) }

    private func makeRepository() -> APIActivityDetailRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DetailURLProtocolStub.self]
        let authSession = AuthSession(service: "test.activityDetail.\(UUID())")
        authSession.clear()
        DetailURLProtocolStub.requests.value = []
        DetailURLProtocolStub.bodies.value = []
        return APIActivityDetailRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private var detailJSON: Data {
        Data("""
        {
          "id": "\(activityId)",
          "title": "Sortie du matin",
          "description": "Belle boucle",
          "sportTypeCode": "ride",
          "startedAt": "2026-10-02T12:32:00.123Z",
          "endedAt": "2026-10-02T14:12:00.000Z",
          "visibility": "followers",
          "processingStatus": "processed",
          "locationName": "Annecy, Haute-Savoie",
          "stats": {
            "distanceM": 42195.5, "movingTimeS": 5400, "elapsedTimeS": 6000, "elevationGainM": null,
            "avgSpeedMs": 7.8, "maxSpeedMs": 15.2, "avgHeartRate": 142, "maxHeartRate": null, "calories": 900
          },
          "map": { "polyline": "_p~iF~ps|U_ulLnnqC", "precision": 5 },
          "author": { "id": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11", "displayName": "Camille Martin", "avatarUrl": null },
          "engagement": { "kudosCount": 3, "commentCount": 1, "viewerHasKudoed": true },
          "viewerIsAuthor": false,
          "updatedAt": "2026-10-03T08:00:00.000Z"
        }
        """.utf8)
    }

    @Test func decodesTheDetail() async throws {
        let repository = makeRepository()
        let json = detailJSON
        DetailURLProtocolStub.handler.value = { _ in (200, json) }

        let detail = try await repository.detail(id: id)

        #expect(DetailURLProtocolStub.requests.value.map(\.url?.path) == ["/v1/activities/\(activityId)"])
        #expect(detail.id == id)
        #expect(detail.title == "Sortie du matin")
        #expect(detail.description == "Belle boucle")
        #expect(detail.sport == .ride)
        #expect(detail.visibility == .followers)
        #expect(abs(detail.startedAt.timeIntervalSince1970 - 1_790_944_320.123) < 0.000_5)
        #expect(detail.locationName == "Annecy, Haute-Savoie")
        #expect(detail.stats == ActivityStats(
            distance: Distance(meters: 42_195.5),
            movingTime: .seconds(5_400),
            elapsedTime: .seconds(6_000),
            elevationGain: nil,
            avgSpeedMs: 7.8,
            maxSpeedMs: 15.2,
            avgHeartRate: 142,
            maxHeartRate: nil,
            calories: 900
        ))
        #expect(detail.route == EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC"))
        #expect(detail.author == ActivityAuthor(id: "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11", displayName: "Camille Martin", avatarURL: nil))
        #expect(detail.engagement == ActivityEngagement(kudosCount: 3, commentCount: 1, viewerHasKudoed: true))
        #expect(!detail.viewerIsAuthor)
    }

    /// No description, place, stats or map yet: all nil; an empty description too.
    @Test func decodesAnActivityWithoutOptionalParts() async throws {
        let repository = makeRepository()
        DetailURLProtocolStub.handler.value = { [activityId] _ in
            (200, Data("""
            {
              "id": "\(activityId)", "title": "Course", "description": "", "sportTypeCode": "run",
              "startedAt": "2026-10-02T12:32:00.000Z", "endedAt": "2026-10-02T13:00:00.000Z",
              "visibility": "private", "processingStatus": "processed",
              "stats": null, "map": null,
              "author": { "id": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11", "displayName": "Camille", "avatarUrl": "https://cdn.test/a.png" },
              "engagement": { "kudosCount": 0, "commentCount": 0, "viewerHasKudoed": false },
              "viewerIsAuthor": true, "updatedAt": "2026-10-02T13:00:00.000Z"
            }
            """.utf8))
        }

        let detail = try await repository.detail(id: id)

        #expect(detail.description == nil)
        #expect(detail.locationName == nil)
        #expect(detail.stats == nil)
        #expect(detail.route == nil)
        #expect(detail.author.avatarURL == URL(string: "https://cdn.test/a.png"))
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()

        DetailURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"activity_not_found","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.notFound) { try await repository.detail(id: id) }

        DetailURLProtocolStub.handler.value = { _ in (401, Data()) }
        await #expect(throws: ActivityDetailError.unauthorized) { try await repository.detail(id: id) }

        DetailURLProtocolStub.handler.value = { _ in
            (500, Data(#"{"error":{"code":"internal_error","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.server(code: "internal_error")) { try await repository.detail(id: id) }
    }

    /// `PATCH /v1/activities/:id` (ADR-033 §4): every field sent, the server's detail back.
    @Test func sendsTheEditAndDecodesTheStoredDetail() async throws {
        let repository = makeRepository()
        let json = detailJSON
        DetailURLProtocolStub.handler.value = { _ in (200, json) }
        let edit = ActivityEdit(title: "Sortie vélo", description: "Avec Paul", sport: .ride, visibility: .followers)

        let detail = try await repository.update(id: id, with: edit)

        let request = try #require(DetailURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/activities/\(activityId)")
        let body = try #require(DetailURLProtocolStub.bodies.value.first)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent == ["title": "Sortie vélo", "description": "Avec Paul", "sportTypeCode": "ride", "visibility": "followers"])
        #expect(detail.id == id)
        #expect(detail.title == "Sortie du matin")
    }

    /// The generated type cannot send `null`: an empty string clears the description (t92).
    @Test func aClearedDescriptionIsSentEmpty() async throws {
        let repository = makeRepository()
        let json = detailJSON
        DetailURLProtocolStub.handler.value = { _ in (200, json) }

        _ = try await repository.update(id: id, with: ActivityEdit(title: "Course", description: nil, sport: .run, visibility: .private))

        let body = try #require(DetailURLProtocolStub.bodies.value.first)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["description"] == "")
        #expect(sent["visibility"] == "private")
    }

    @Test func mapsEditErrors() async {
        let repository = makeRepository()
        let edit = ActivityEdit(title: "Course", description: nil, sport: .ride, visibility: .public)

        DetailURLProtocolStub.handler.value = { _ in
            (422, Data(#"{"error":{"code":"activity_too_short_for_sport","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.invalid(code: "activity_too_short_for_sport")) {
            try await repository.update(id: id, with: edit)
        }

        DetailURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"activity_not_found","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.notFound) { try await repository.update(id: id, with: edit) }

        DetailURLProtocolStub.handler.value = { _ in
            (409, Data(#"{"error":{"code":"activity_not_editable","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.server(code: "activity_not_editable")) {
            try await repository.update(id: id, with: edit)
        }
    }

    /// `DELETE /v1/activities/:id` (ADR-033 §6): `204`, no body.
    @Test func deletesTheActivity() async throws {
        let repository = makeRepository()
        DetailURLProtocolStub.handler.value = { _ in (204, Data()) }

        try await repository.delete(id: id)

        let request = try #require(DetailURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/activities/\(activityId)")
    }

    /// #94: a second `DELETE` gets `404 not_found`; `409 not_deletable` while processing.
    @Test func mapsDeleteErrors() async {
        let repository = makeRepository()

        DetailURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.notFound) { try await repository.delete(id: id) }

        DetailURLProtocolStub.handler.value = { _ in
            (409, Data(#"{"error":{"code":"not_deletable","message":"x"}}"#.utf8))
        }
        await #expect(throws: ActivityDetailError.server(code: "not_deletable")) { try await repository.delete(id: id) }
    }
}
