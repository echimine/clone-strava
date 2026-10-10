import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class MetricsURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        do {
            let (status, body) = try Self.handler.value?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct APIItineraryMetricsPreviewerTests {
    private let request = ItineraryMetricsRequest(
        waypoints: [
            Coordinate(latitude: 45.9, longitude: 6.12),
            Coordinate(latitude: 45.901, longitude: 6.121),
            Coordinate(latitude: 45.902, longitude: 6.12),
        ],
        legs: [.follow(EncodedPolyline(value: "_ibexA_qgpJ_ibE_ibE", precision: 6)), .straight]
    )

    private func makePreviewer() -> APIItineraryMetricsPreviewer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetricsURLProtocolStub.self]
        let authSession = AuthSession(service: "test.itinerary-metrics.\(UUID())")
        authSession.clear()
        MetricsURLProtocolStub.requests.value = []
        return APIItineraryMetricsPreviewer(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    @Test func postsTheTrackAndReadsTheMetricsTheAPIComputed() async throws {
        let previewer = makePreviewer()
        MetricsURLProtocolStub.handler.value = { _ in
            (200, Data(#"{ "distanceM": 1234.5, "elevationGainM": 87.2, "elevationSource": "mixed" }"#.utf8))
        }

        let metrics = try await previewer.metrics(for: request)

        #expect(metrics == ItineraryMetrics(distance: Distance(meters: 1_234.5), elevationGain: 87.2, elevationSource: .mixed))
        let sent = try #require(MetricsURLProtocolStub.requests.value.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path == "/v1/itineraries/metrics-preview")
        let data = try #require(sent.bodyData)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(body == [
            "waypoints": [
                ["lat": 45.9, "lon": 6.12],
                ["lat": 45.901, "lon": 6.121],
                ["lat": 45.902, "lon": 6.12],
            ],
            "legs": [
                ["mode": "follow", "polyline6": "_ibexA_qgpJ_ibE_ibE"],
                ["mode": "straight"],
            ],
        ] as NSDictionary)
    }

    @Test(arguments: [("ign", ElevationSource.ign), ("open_meteo", .openMeteo)])
    func readsEveryElevationSource(code: String, source: ElevationSource) async throws {
        let previewer = makePreviewer()
        MetricsURLProtocolStub.handler.value = { _ in
            (200, Data(#"{ "distanceM": 10, "elevationGainM": 0, "elevationSource": "\#(code)" }"#.utf8))
        }

        #expect(try await previewer.metrics(for: request).elevationSource == source)
    }

    @Test func anElevationProviderFailureMakesThePreviewUnavailable() async {
        let previewer = makePreviewer()
        MetricsURLProtocolStub.handler.value = { _ in
            (503, Data(#"{ "error": { "code": "elevation_unavailable" } }"#.utf8))
        }

        await #expect(throws: ItineraryMetricsError.unavailable) {
            try await previewer.metrics(for: request)
        }
    }

    @Test func anUnexpectedAnswerMakesThePreviewUnavailable() async {
        let previewer = makePreviewer()
        MetricsURLProtocolStub.handler.value = { _ in
            (200, Data(#"{ "distanceM": 10, "elevationGainM": 0, "elevationSource": "srtm" }"#.utf8))
        }

        await #expect(throws: ItineraryMetricsError.unavailable) {
            try await previewer.metrics(for: request)
        }
    }

    @Test func noConnectionIsReportedAsOffline() async {
        let previewer = makePreviewer()
        MetricsURLProtocolStub.handler.value = { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: ItineraryMetricsError.offline) {
            try await previewer.metrics(for: request)
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
