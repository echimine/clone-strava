import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIActivityDetailRepositoryTests`: suites run in parallel.
private final class ResultsURLProtocolStub: URLProtocol, @unchecked Sendable {
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

/// `GET /v1/activities/:id/results` and `DELETE /v1/activities/:id/best-efforts/:distanceM`
/// (ADR-039 §12) through the generated `ActivityResultsDto_Output`.
@Suite(.serialized)
struct APIActivityResultsRepositoryTests {
    private let activityId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private var id: ActivityID { ActivityID(UUID(uuidString: activityId)!) }

    private func makeRepository() -> APIActivityResultsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResultsURLProtocolStub.self]
        let authSession = AuthSession(service: "test.activityResults.\(UUID())")
        authSession.clear()
        ResultsURLProtocolStub.requests.value = []
        return APIActivityResultsRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    @Test func decodesTheResults() async throws {
        let repository = makeRepository()
        ResultsURLProtocolStub.handler.value = { _ in
            (200, Data(#"""
            {
              "matchingInProgress": true,
              "poolLengthM": 25,
              "bestEfforts": [
                { "distanceM": 21097.5, "elapsedTimeMs": 5400500, "medal": "silver", "isFirst": false, "isCurrentRecord": false, "removable": true },
                { "distanceM": 42195, "elapsedTimeMs": 12000000, "medal": null, "isFirst": true, "isCurrentRecord": true, "removable": false }
              ],
              "efforts": [{
                "id": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11",
                "segment": { "id": "1b4e28ba-2fa1-41d2-883f-0016d3cca427", "name": "Reference Albigny", "distanceM": 370, "verified": true },
                "elapsedTimeS": 131, "medal": "gold", "isFirstPass": true, "localLegend": false,
                "startPoint": { "lat": 45.9, "lon": 6.13 }
              }]
            }
            """#.utf8))
        }

        let results = try await repository.results(of: id)

        let request = try #require(ResultsURLProtocolStub.requests.value.first)
        #expect(request.url?.path == "/v1/activities/\(activityId)/results")
        #expect(results == ActivityResults(
            matchingInProgress: true,
            poolLength: Distance(meters: 25),
            bestEfforts: [
                BestEffortResult(distanceM: 21_097.5, elapsedTime: .milliseconds(5_400_500), medal: .silver,
                                 isFirst: false, isCurrentRecord: false, removable: true),
                BestEffortResult(distanceM: 42_195, elapsedTime: .milliseconds(12_000_000), medal: nil,
                                 isFirst: true, isCurrentRecord: true, removable: false),
            ],
            efforts: [SegmentEffortResult(
                id: "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11",
                segmentID: "1b4e28ba-2fa1-41d2-883f-0016d3cca427",
                segmentName: "Reference Albigny",
                segmentDistance: Distance(meters: 370),
                verified: true,
                elapsedTime: .seconds(131),
                medal: .gold,
                isFirstPass: true,
                localLegend: false,
                startPoint: Coordinate(latitude: 45.9, longitude: 6.13)
            )]
        ))
    }

    @Test func removesABestEffort() async throws {
        let repository = makeRepository()
        ResultsURLProtocolStub.handler.value = { _ in (204, Data()) }

        try await repository.removeBestEffort(of: id, distanceM: 21_097.5)

        let request = try #require(ResultsURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/activities/\(activityId)/best-efforts/21097.5")
    }

    @Test func aWholeDistanceIsSentWithoutDecimals() async throws {
        let repository = makeRepository()
        ResultsURLProtocolStub.handler.value = { _ in (204, Data()) }

        try await repository.removeBestEffort(of: id, distanceM: 1_000)

        #expect(ResultsURLProtocolStub.requests.value.first?.url?.path == "/v1/activities/\(activityId)/best-efforts/1000")
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()
        ResultsURLProtocolStub.handler.value = { _ in
            (404, Data(#"{"error":{"code":"activity_not_found","message":"x"}}"#.utf8))
        }

        await #expect(throws: ActivityDetailError.notFound) { try await repository.results(of: id) }
    }
}
