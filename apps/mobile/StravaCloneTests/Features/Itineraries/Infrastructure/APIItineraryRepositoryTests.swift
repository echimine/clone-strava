import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class ItineraryURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.requests.value.append(recorded)
        let (status, body) = Self.handler.value?(recorded) ?? (500, Data())
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

/// `/v1/itineraries` over a stubbed network, then into the real GRDB cache: saving and the
/// full resync (ADR-030 §8).
@Suite(.serialized)
struct APIItineraryRepositoryTests {
    private func makeRepository() -> APIItineraryRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ItineraryURLProtocolStub.self]
        let authSession = AuthSession(service: "test.itineraries.\(UUID())")
        authSession.clear()
        ItineraryURLProtocolStub.requests.value = []
        ItineraryURLProtocolStub.handler.value = nil
        return APIItineraryRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    // MARK: Fixtures

    private let creation = ItineraryCreation(
        id: .fixture(7),
        name: "Tour du lac",
        sport: .hike,
        waypoints: [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.92, longitude: 6.12)],
        legs: [.follow(EncodedPolyline(value: "_mopvA_cptJ_pR?_pR?", precision: 6))]
    )

    private func detailJSON(id: ItineraryID = .fixture(7)) -> Data {
        Data("""
        {
          "id": "\(id)", "name": "Tour du lac", "sportTypeCode": "hike",
          "distanceM": 2224, "elevationGainM": 87.5, "elevationSource": "mixed",
          "waypoints": [{ "lat": 45.9, "lon": 6.12 }, { "lat": 45.92, "lon": 6.12 }],
          "legs": [{ "mode": "follow", "polyline6": "_mopvA_cptJ_pR?_pR?" }],
          "track": { "polyline6": "_mopvA_cptJ_pR?_pR?", "altitudesM": [446.5, 480, 534] },
          "createdAt": "2026-10-10T07:00:00.500Z", "updatedAt": "2026-10-10T08:00:00.500Z"
        }
        """.utf8)
    }

    private func item(_ number: Int, minutes: Int) -> String {
        """
        { "id": "\(ItineraryID.fixture(number))", "name": "Itinéraire \(number)", "sportTypeCode": "ride",
          "distanceM": 42195.5, "elevationGainM": 640, "mapPolyline": "_p~iF~ps|U",
          "updatedAt": "2026-10-10T08:\(String(format: "%02d", minutes)):00.500Z" }
        """
    }

    private func page(_ items: [String], next: String?) -> Data {
        Data(#"{ "items": [\#(items.joined(separator: ","))], "nextCursor": \#(next.map { "\"\($0)\"" } ?? "null") }"#.utf8)
    }

    // MARK: Save

    @Test func createSendsTheAppIdTheWaypointsAndTheLegs() async throws {
        let repository = makeRepository()
        let json = detailJSON()
        ItineraryURLProtocolStub.handler.value = { _ in (201, json) }

        let created = try await repository.create(creation)

        let request = try #require(ItineraryURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/itineraries")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["id"] as? String == "00000000-0000-4000-8000-000000000007")
        #expect(body["name"] as? String == "Tour du lac")
        #expect(body["sportTypeCode"] as? String == "hike")
        let waypoints = try #require(body["waypoints"] as? [[String: Double]])
        #expect(waypoints == [["lat": 45.9, "lon": 6.12], ["lat": 45.92, "lon": 6.12]])
        let legs = try #require(body["legs"] as? [[String: String]])
        #expect(legs == [["mode": "follow", "polyline6": "_mopvA_cptJ_pR?_pR?"]])

        #expect(created == .new(ItineraryDetail.fixture(7, name: "Tour du lac", sport: .hike, elevationSource: .mixed)))
    }

    @Test func aStraightLegCarriesNoGeometry() async throws {
        let repository = makeRepository()
        let json = detailJSON()
        ItineraryURLProtocolStub.handler.value = { _ in (201, json) }
        let straight = ItineraryCreation(
            id: creation.id, name: creation.name, sport: .run, waypoints: creation.geometry.waypoints, legs: [.straight]
        )

        _ = try await repository.create(straight)

        let request = try #require(ItineraryURLProtocolStub.requests.value.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["legs"] as? [[String: String]] == [["mode": "straight"]])
    }

    /// The answer of the first try is lost: the replay sends the same id and the API
    /// answers `200` with the Itinerary it already has (ADR-030 §6).
    @Test func aReplayAfterACutSendsTheSameIdAndGetsTheSameItinerary() async throws {
        let repository = makeRepository()
        let json = detailJSON()
        let attempts = Locked(0)
        ItineraryURLProtocolStub.handler.value = { _ in
            attempts.value += 1
            return attempts.value == 1 ? (502, Data()) : (200, json)
        }

        await #expect(throws: ItineraryError.server(code: nil)) { try await repository.create(creation) }
        let created = try await repository.create(creation)

        let ids = try ItineraryURLProtocolStub.requests.value.map { request in
            try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])["id"] as? String
        }
        #expect(ids == ["00000000-0000-4000-8000-000000000007", "00000000-0000-4000-8000-000000000007"])
        #expect(created.detail.id == .fixture(7))
        #expect(created.isReplay)
    }

    @Test func mapsErrors() async {
        let repository = makeRepository()

        ItineraryURLProtocolStub.handler.value = { _ in
            (503, Data(#"{"error":{"code":"elevation_unavailable","message":"x","retryAfterS":5}}"#.utf8))
        }
        await #expect(throws: ItineraryError.unavailable) { try await repository.create(creation) }

        ItineraryURLProtocolStub.handler.value = { _ in (409, Data(#"{"error":{"code":"id_conflict","message":"x"}}"#.utf8)) }
        await #expect(throws: ItineraryError.conflict) { try await repository.create(creation) }

        ItineraryURLProtocolStub.handler.value = { _ in (422, Data(#"{"error":{"code":"validation_error","message":"x"}}"#.utf8)) }
        await #expect(throws: ItineraryError.invalid(code: "validation_error")) { try await repository.create(creation) }

        ItineraryURLProtocolStub.handler.value = { _ in (401, Data()) }
        await #expect(throws: ItineraryError.unauthorized) { try await repository.page(cursor: nil) }
    }

    // MARK: Detail

    @Test func readsTheDetailWithItsTrackAndAltitudes() async throws {
        let repository = makeRepository()
        let json = detailJSON()
        ItineraryURLProtocolStub.handler.value = { _ in (200, json) }

        let detail = try await repository.detail(id: .fixture(7))

        let request = try #require(ItineraryURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/itineraries/00000000-0000-4000-8000-000000000007")
        #expect(detail == ItineraryDetail.fixture(7, name: "Tour du lac", sport: .hike, elevationSource: .mixed))
    }

    @Test func anUnknownDetailIsNotFound() async {
        let repository = makeRepository()
        ItineraryURLProtocolStub.handler.value = { _ in (404, Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8)) }

        await #expect(throws: ItineraryError.notFound) { try await repository.detail(id: .fixture(7)) }
    }

    // MARK: Resync

    @MainActor
    @Test func aResyncReadsEveryPageAndDeletesTheRowsNoLongerReturned() async throws {
        let repository = makeRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        try await cache.save(.fixture(9), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        try await cache.replaceSummaries(with: [.fixture(1, name: "Ancien nom"), .fixture(9)])
        let first = page([item(3, minutes: 50), item(1, minutes: 40)], next: "page2")
        let second = page([item(2, minutes: 10)], next: nil)
        ItineraryURLProtocolStub.handler.value = { request in
            request.url?.query?.contains("cursor=page2") == true ? (200, second) : (200, first)
        }
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache)

        try await synchronizer.refresh()

        // The list pages only: the details of the new rows are prefetched afterwards.
        let cursors = ItineraryURLProtocolStub.requests.value.filter { $0.url?.path == "/v1/itineraries" }.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
        }
        #expect(cursors == [nil, "page2"])
        let summaries = try await cache.summaries(limit: 20)
        #expect(summaries.map(\.id) == [.fixture(3), .fixture(1), .fixture(2)])
        #expect(summaries.map(\.name) == ["Itinéraire 3", "Itinéraire 1", "Itinéraire 2"])
        #expect(try await cache.detail(id: .fixture(9)) == nil)
    }

    @MainActor
    @Test func aResyncThatFailsMidwayKeepsTheCacheAsItWas() async throws {
        let repository = makeRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(9)])
        let first = page([item(3, minutes: 50)], next: "page2")
        ItineraryURLProtocolStub.handler.value = { request in
            request.url?.query?.contains("cursor=page2") == true ? (500, Data()) : (200, first)
        }
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache)

        await #expect(throws: ItineraryError.server(code: nil)) { try await synchronizer.refresh() }

        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(1), .fixture(9)])
    }

    // MARK: List

    @Test func readsAPageOfTheList() async throws {
        let repository = makeRepository()
        let json = page([item(1, minutes: 30)], next: "abc")
        ItineraryURLProtocolStub.handler.value = { _ in (200, json) }

        let result = try await repository.page(cursor: "prev")

        let request = try #require(ItineraryURLProtocolStub.requests.value.first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/itineraries")
        #expect(components.queryItems == [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: "prev")])
        #expect(result == ItineraryPage(
            items: [.fixture(1, sport: .ride, distance: 42_195.5, elevationGain: 640, mapPolyline: "_p~iF~ps|U", updatedMinutes: 30)],
            nextCursor: "abc"
        ))
    }
}
