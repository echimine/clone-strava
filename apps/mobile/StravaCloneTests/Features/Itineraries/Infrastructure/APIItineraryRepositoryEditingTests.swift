import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIItineraryRepositoryTests`: suites run in parallel.
private final class ItineraryEditingURLProtocolStub: URLProtocol, @unchecked Sendable {
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

/// "Modifier" over a stubbed network (ADR-030 §6): `GET /:id` for the Waypoints and Legs,
/// `PUT /:id` to save the edit.
@Suite(.serialized)
struct APIItineraryRepositoryEditingTests {
    private func makeRepository() -> APIItineraryRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ItineraryEditingURLProtocolStub.self]
        let authSession = AuthSession(service: "test.itineraries.editing.\(UUID())")
        authSession.clear()
        ItineraryEditingURLProtocolStub.requests.value = []
        ItineraryEditingURLProtocolStub.handler.value = nil
        return APIItineraryRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    /// The API draws a `straight` Leg itself, so it answers every Leg with a geometry.
    private let detailJSON = Data("""
    {
      "id": "00000000-0000-4000-8000-000000000007", "name": "Tour du lac", "sportTypeCode": "hike",
      "distanceM": 2224, "elevationGainM": 87.5, "elevationSource": "ign",
      "waypoints": [{ "lat": 45.9, "lon": 6.12 }, { "lat": 45.91, "lon": 6.12 }, { "lat": 45.92, "lon": 6.12 }],
      "legs": [
        { "mode": "follow", "polyline6": "_mopvA_cptJ_pR?" },
        { "mode": "straight", "polyline6": "_}rpvA_cptJ_pR?" }
      ],
      "track": { "polyline6": "_mopvA_cptJ_pR?_pR?", "altitudesM": [446.5, 480, 534] },
      "createdAt": "2026-10-10T07:00:00.500Z", "updatedAt": "2026-10-10T08:00:00.500Z"
    }
    """.utf8)

    @Test func loadingReadsTheStoredWaypointsAndLegs() async throws {
        let repository = makeRepository()
        let json = detailJSON
        ItineraryEditingURLProtocolStub.handler.value = { _ in (200, json) }

        let saved = try await repository.savedItinerary(id: .fixture(7))

        let request = try #require(ItineraryEditingURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/itineraries/00000000-0000-4000-8000-000000000007")
        #expect(saved == SavedItinerary(
            id: .fixture(7),
            name: "Tour du lac",
            sport: .hike,
            waypoints: [
                Coordinate(latitude: 45.9, longitude: 6.12),
                Coordinate(latitude: 45.91, longitude: 6.12),
                Coordinate(latitude: 45.92, longitude: 6.12),
            ],
            legs: [.follow(EncodedPolyline(value: "_mopvA_cptJ_pR?", precision: 6)), .straight]
        ))
    }

    @Test func anItineraryForAnotherSportCannotBeEdited() async throws {
        let repository = makeRepository()
        let json = Data(String(decoding: detailJSON, as: UTF8.self).replacingOccurrences(of: "\"hike\"", with: "\"swim\"").utf8)
        ItineraryEditingURLProtocolStub.handler.value = { _ in (200, json) }

        await #expect(throws: ItineraryError.server(code: nil)) {
            try await repository.savedItinerary(id: .fixture(7))
        }
    }

    @Test func aGoneItineraryIsNotFound() async {
        let repository = makeRepository()
        ItineraryEditingURLProtocolStub.handler.value = { _ in (404, Data(#"{"error":{"code":"not_found"}}"#.utf8)) }

        await #expect(throws: ItineraryError.notFound) {
            try await repository.savedItinerary(id: .fixture(7))
        }
    }

    @Test func updatePutsTheWholeItineraryOnTheSameId() async throws {
        let repository = makeRepository()
        let json = detailJSON
        ItineraryEditingURLProtocolStub.handler.value = { _ in (200, json) }
        let edit = ItineraryCreation(
            id: .fixture(7),
            name: "Tour du lac",
            sport: .ride,
            waypoints: [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.92, longitude: 6.12)],
            legs: [.follow(EncodedPolyline(value: "_mopvA_cptJ_pR?_pR?", precision: 6))]
        )

        let detail = try await repository.update(edit)

        let request = try #require(ItineraryEditingURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/itineraries/00000000-0000-4000-8000-000000000007")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["id"] == nil)
        #expect(body["name"] as? String == "Tour du lac")
        #expect(body["sportTypeCode"] as? String == "ride")
        #expect(body["waypoints"] as? [[String: Double]] == [["lat": 45.9, "lon": 6.12], ["lat": 45.92, "lon": 6.12]])
        #expect(body["legs"] as? [[String: String]] == [["mode": "follow", "polyline6": "_mopvA_cptJ_pR?_pR?"]])
        #expect(detail.id == .fixture(7))
        #expect(detail.updatedAt == .fixture())
    }

    /// An elevation provider failed (ADR-030 §3): worth retrying.
    @Test func anUnavailableElevationProviderIsRetryable() async {
        let repository = makeRepository()
        ItineraryEditingURLProtocolStub.handler.value = { _ in (503, Data(#"{"error":{"code":"elevation_unavailable"}}"#.utf8)) }
        let edit = ItineraryCreation(
            id: .fixture(7), name: "Tour", sport: .run,
            waypoints: [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.92, longitude: 6.12)],
            legs: [.straight]
        )

        await #expect(throws: ItineraryError.unavailable) {
            try await repository.update(edit)
        }
    }
}
