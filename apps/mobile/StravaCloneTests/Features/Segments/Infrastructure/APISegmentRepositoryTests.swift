import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIModerationRepositoryTests`: suites run in parallel.
private final class SegmentURLProtocolStub: URLProtocol, @unchecked Sendable {
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

/// `GET /v1/segments/:id` and its `leaderboard` (ADR-039 §12) decoded with the generated types,
/// the query of the chips, and the errors the sheet tells apart.
@Suite(.serialized)
struct APISegmentRepositoryTests {
    private let segmentId = "5d0c1e2f-5b1c-4f3e-9d43-3c2a1b0e9f01"
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f02"
    private let effortId = "7c1e2f0e-5b1c-4f3e-9d43-3c2a1b0e9f03"
    private let activityId = "8d1e2f0e-5b1c-4f3e-9d43-3c2a1b0e9f04"

    private func makeRepository() -> APISegmentRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SegmentURLProtocolStub.self]
        let authSession = AuthSession(service: "test.segments.\(UUID())")
        authSession.clear()
        SegmentURLProtocolStub.requests.value = []
        var repository = APISegmentRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
        repository.timeZone = { TimeZone(identifier: "Europe/Paris")! }
        return repository
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        SegmentURLProtocolStub.handler.value = { _ in (status, body) }
    }

    private var entry: String {
        #"{ "rank": 2, "athlete": { "id": "\#(athleteId)", "displayName": "Léa Martin", "avatarUrl": null }, "effortId": "\#(effortId)", "activityId": "\#(activityId)", "elapsedTimeS": 245, "startedAt": "2026-06-01T08:00:00.000Z" }"#
    }

    private var leaderboard: String {
        #"{ "limited": true, "entries": [\#(entry)], "me": \#(entry), "localLegend": { "legend": { "athlete": { "id": "\#(athleteId)", "displayName": "Léa Martin", "avatarUrl": null }, "effortCount": 4 }, "myEffortCount": 4 }, "athleteCount": 12, "nextCursor": null }"#
    }

    @Test func decodesTheSheet() async throws {
        respond(200, #"""
        { "id": "\#(segmentId)", "name": "Col du test", "sportTypeCode": "ride", "verified": true,
          "distanceM": 1200, "elevationGainM": 100, "avgGrade": 8.3, "maxGrade": 12, "climbCategory": "hc",
          "track": { "polyline6": "_ibE_ibE", "altitudesM": [500] },
          "starred": true, "favoriteCount": 337, "isMine": false, "canDelete": false, "historyMatching": true,
          "myEfforts": [{ "id": "\#(effortId)", "activityId": "\#(activityId)", "activityVisibility": "private",
            "startedAt": "2026-06-01T08:00:00.000Z", "elapsedTimeS": 245, "medal": "gold", "standing": false,
            "isLeaderboardLine": false, "rank": null }],
          "myRecord": null,
          "localLegend": { "legend": null, "myEffortCount": 0 },
          "leaderboard": \#(leaderboard) }
        """#)

        let sheet = try await makeRepository().sheet(id: segmentId)

        #expect(sheet.name == "Col du test")
        #expect(sheet.climbCategory == .hc)
        #expect(sheet.isStarred && sheet.favoriteCount == 337 && sheet.isMatchingHistory)
        #expect(sheet.myEfforts.first?.medal == .gold)
        #expect(sheet.myEfforts.first?.isPublicActivity == false)
        #expect(sheet.myRank == 2)
        #expect(sheet.leaderboard.localLegend.holder?.effortCount == 4)
        #expect(SegmentURLProtocolStub.requests.value.first?.url?.path == "/v1/segments/\(segmentId)")
    }

    @Test func sendsTheChipsAndTheTimeZoneOfAPeriod() async throws {
        respond(200, leaderboard)

        let board = try await makeRepository().leaderboard(
            id: segmentId,
            selection: LeaderboardSelection(gender: .female, filter: .period(.week)),
            cursor: "c1"
        )

        #expect(board.athleteCount == 12)
        let query = URLComponents(url: SegmentURLProtocolStub.requests.value[0].url!, resolvingAgainstBaseURL: false)!.queryItems
        #expect(query == [
            URLQueryItem(name: "gender", value: "female"),
            URLQueryItem(name: "filter", value: "period"),
            URLQueryItem(name: "value", value: "week"),
            URLQueryItem(name: "tz", value: "Europe/Paris"),
            URLQueryItem(name: "cursor", value: "c1"),
        ])
    }

    @Test func tellsPremiumRequiredAndADeletedSegmentApart() async {
        let repository = makeRepository()

        respond(403, #"{ "error": { "code": "premium_required", "message": "" } }"#)
        await #expect(throws: SegmentError.premiumRequired) {
            try await repository.leaderboard(id: segmentId, selection: LeaderboardSelection(gender: .male), cursor: nil)
        }
        respond(404, #"{ "error": { "code": "segment_not_found", "message": "" } }"#)
        await #expect(throws: SegmentError.notFound) { try await repository.sheet(id: segmentId) }
        respond(409, #"{ "error": { "code": "has_other_efforts", "message": "" } }"#)
        await #expect(throws: SegmentError.hasOtherEfforts) { try await repository.delete(id: segmentId) }
    }
}
