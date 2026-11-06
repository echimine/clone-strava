import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIItineraryRepositoryTests`: suites run in parallel.
private final class FavoriteSegmentsURLProtocolStub: URLProtocol, @unchecked Sendable {
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

/// `GET /v1/me/segment-favorites` over a stubbed network (ADR-039 §12, ADR-025): Plus ›
/// « Segments », by pages, a sport without a map left out.
@Suite(.serialized)
struct APIFavoriteSegmentsRepositoryTests {
    private func makeRepository() -> APIFavoriteSegmentsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteSegmentsURLProtocolStub.self]
        let authSession = AuthSession(service: "test.favoriteSegments.\(UUID())")
        authSession.clear()
        FavoriteSegmentsURLProtocolStub.requests.value = []
        FavoriteSegmentsURLProtocolStub.handler.value = nil
        return APIFavoriteSegmentsRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            ),
            pageSize: 2
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        FavoriteSegmentsURLProtocolStub.handler.value = { _ in (status, body) }
    }

    @Test func decodesAPageAndSendsItsSizeAndCursor() async throws {
        let repository = makeRepository()
        respond(200, """
        { "items": [
            { "id": "seg-1", "sport": "ride", "name": "Montée du Semnoz", "verified": true, "distanceM": 6800,
              "avgGradePct": 7.4, "climbCategory": "2", "myBestTimeS": 1234 },
            { "id": "seg-2", "sport": "run", "name": "Bord du lac", "verified": false, "distanceM": 2000,
              "avgGradePct": 0.4, "climbCategory": null, "myBestTimeS": null }
          ], "nextCursor": "c2" }
        """)

        let page = try await repository.page(after: "c1")

        #expect(page == FavoriteSegmentsPage(
            items: [
                FavoriteSegment(
                    id: "seg-1", sport: .ride, name: "Montée du Semnoz", isVerified: true,
                    distance: Distance(meters: 6_800), averageGrade: 7.4, climbCategory: .cat2,
                    myBestTime: .seconds(1_234)
                ),
                FavoriteSegment(
                    id: "seg-2", sport: .run, name: "Bord du lac", isVerified: false,
                    distance: Distance(meters: 2_000), averageGrade: 0.4, climbCategory: nil, myBestTime: nil
                ),
            ],
            nextCursor: "c2"
        ))
        let request = try #require(FavoriteSegmentsURLProtocolStub.requests.value.first)
        #expect(request.url?.path == "/v1/me/segment-favorites")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "limit", value: "2"), URLQueryItem(name: "cursor", value: "c1")])
    }

    @Test func theFirstPageHasNoCursorAndAnUnknownSportIsLeftOut() async throws {
        let repository = makeRepository()
        respond(200, """
        { "items": [{ "id": "seg-3", "sport": "swim", "name": "Lac", "verified": false, "distanceM": 500,
            "avgGradePct": 0, "climbCategory": null, "myBestTimeS": null }], "nextCursor": null }
        """)

        let page = try await repository.page(after: nil)

        #expect(page == FavoriteSegmentsPage(items: [], nextCursor: nil))
        let request = try #require(FavoriteSegmentsURLProtocolStub.requests.value.first)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "limit", value: "2")])
    }

    @Test func aServerFailureIsTold() async {
        let repository = makeRepository()
        respond(500, "")

        await #expect(throws: SegmentError.server) { try await repository.page(after: nil) }
    }
}
