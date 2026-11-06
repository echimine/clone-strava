import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIItineraryRepositoryTests`: suites run in parallel.
private final class SegmentMapURLProtocolStub: URLProtocol, @unchecked Sendable {
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

/// `GET /v1/segments` over a stubbed network (ADR-039 §12): the zone and filters in the query,
/// the cards decoded, `zone_too_large` told apart.
@Suite(.serialized)
struct APISegmentMapRepositoryTests {
    private func makeRepository() -> APISegmentMapRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SegmentMapURLProtocolStub.self]
        let authSession = AuthSession(service: "test.segmentMap.\(UUID())")
        authSession.clear()
        SegmentMapURLProtocolStub.requests.value = []
        SegmentMapURLProtocolStub.handler.value = nil
        return APISegmentMapRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private let area = MapArea(
        southWest: Coordinate(latitude: 45.88, longitude: 6.1),
        northEast: Coordinate(latitude: 45.92, longitude: 6.16),
        zoom: 12
    )

    @Test func sendsTheZoneAndFiltersAndDecodesTheCards() async throws {
        let repository = makeRepository()
        SegmentMapURLProtocolStub.handler.value = { _ in
            (200, Data("""
            {"items":[{"id":"7c0e3f7e-3c39-4e0e-9a43-2f8ad2d9a5b1","sportTypeCode":"ride","name":"Col de Leschaux",
            "verified":true,"starred":false,"distanceM":6800,"averageGradePct":7.4,"climbCategory":"2",
            "athleteCount":337,"myBestTimeS":null,"leaderTimeS":754,"mapPolyline":"_p~iF~ps|U_ulLnnqC"}]}
            """.utf8))
        }

        let segments = try await repository.segments(in: area, filter: SegmentMapFilter(sport: .ride, favoritesOnly: true))

        let url = try #require(SegmentMapURLProtocolStub.requests.value.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.path == "/v1/segments")
        #expect(items.first { $0.name == "bbox" }?.value == "6.10000,45.88000,6.16000,45.92000")
        #expect(items.first { $0.name == "sport" }?.value == "ride")
        #expect(items.first { $0.name == "favorites" }?.value == "true")
        #expect(segments == [MapSegment(
            id: "7c0e3f7e-3c39-4e0e-9a43-2f8ad2d9a5b1",
            sport: .ride,
            name: "Col de Leschaux",
            isVerified: true,
            isFavorite: false,
            distance: Distance(meters: 6_800),
            averageGradePct: 7.4,
            climbCategory: .cat2,
            athleteCount: 337,
            myBestTime: nil,
            leaderTime: .seconds(754),
            path: [Coordinate(latitude: 38.5, longitude: -120.2), Coordinate(latitude: 40.7, longitude: -120.95)]
        )])
    }

    @Test func aZoneTooLargeIsToldApartFromOtherRefusals() async {
        let repository = makeRepository()
        SegmentMapURLProtocolStub.handler.value = { _ in
            (400, Data(#"{"error":{"code":"zone_too_large","message":"Zoom in"}}"#.utf8))
        }
        await #expect(throws: SegmentError.zoneTooLarge) {
            try await repository.segments(in: area, filter: SegmentMapFilter())
        }

        SegmentMapURLProtocolStub.handler.value = { _ in (500, Data()) }
        await #expect(throws: SegmentError.server) {
            try await repository.segments(in: area, filter: SegmentMapFilter())
        }
    }
}
