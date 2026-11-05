import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIItineraryMetricsPreviewerTests`: suites run in parallel.
private final class SegmentURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, String))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let (status, body) = Self.handler.value?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// `URLSession` hands the body to a `URLProtocol` as a stream.
    var sentBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// `POST /v1/segments/preview` and `POST /v1/segments` (ADR-039 §12): what is sent, what is
/// read back, and how the refusals map.
@Suite(.serialized)
struct APISegmentCreationRepositoryTests {
    private let points = [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.909, longitude: 6.12)]

    private func makeRepository(answering status: Int, _ body: String) -> APISegmentCreationRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SegmentURLProtocolStub.self]
        let authSession = AuthSession(service: "test.segment-creation.\(UUID())")
        authSession.clear()
        SegmentURLProtocolStub.requests.value = []
        SegmentURLProtocolStub.handler.value = { _ in (status, body) }
        return APISegmentCreationRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    @Test func previewSendsTheDrawnPathAndReadsTheServersFigures() async throws {
        let track = EncodedPolyline(encoding: points, precision: 6).value
        let repository = makeRepository(answering: 200, """
        { "distanceM": 1000.5, "elevationGainM": 80, "avgGradePct": 8, "maxGradePct": 9.4,
          "minAltitudeM": 500, "maxAltitudeM": 580, "climbCategory": "4",
          "track": { "polyline6": "\(track)", "altitudesM": [500, 580] },
          "violations": ["loop"], "duplicate": { "id": "seg-2", "name": "Le Semnoz" }, "quotaLeft": 7 }
        """)

        let preview = try await repository.preview(sport: .ride, points: points)

        #expect(preview.figures == SegmentFigures(
            distance: Distance(meters: 1_000.5),
            elevationGain: 80,
            averageGrade: 8,
            maxGrade: 9.4,
            lowestAltitude: 500,
            highestAltitude: 580,
            climbCategory: .cat4
        ))
        #expect(preview.track == points)
        #expect(preview.altitudes == [500, 580])
        #expect(preview.violations == [.loop])
        #expect(preview.duplicate == SegmentRef(id: "seg-2", name: "Le Semnoz"))
        #expect(preview.quotaLeft == 7)
        let sent = try #require(SegmentURLProtocolStub.requests.value.first)
        #expect(sent.url?.path == "/v1/segments/preview")
        let data = try #require(sent.sentBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(body == ["sport": "ride", "points": [["lat": 45.9, "lon": 6.12], ["lat": 45.909, "lon": 6.12]]] as NSDictionary)
    }

    @Test func createReadsTheNewSegment() async throws {
        let repository = makeRepository(answering: 201, #"{ "id": "seg-9", "name": "Col du Semnoz", "sport": "ride" }"#)
        let created = try await repository.create(sport: .ride, name: "Col du Semnoz", points: points)
        #expect(created == SegmentRef(id: "seg-9", name: "Col du Semnoz"))
        #expect(SegmentURLProtocolStub.requests.value.first?.url?.path == "/v1/segments")
    }

    @Test func mapsTheRefusals() async {
        let duplicate = makeRepository(answering: 409, #"{ "error": { "code": "duplicate", "message": "x", "existing": { "id": "seg-2", "name": "Le Semnoz" } } }"#)
        await #expect(throws: SegmentCreationError.duplicate(SegmentRef(id: "seg-2", name: "Le Semnoz"))) {
            try await duplicate.create(sport: .run, name: "Mon Semnoz", points: points)
        }
        let quota = makeRepository(answering: 429, #"{ "error": { "code": "quota_reached", "message": "x" } }"#)
        await #expect(throws: SegmentCreationError.quotaReached) {
            try await quota.create(sport: .run, name: "Mon Semnoz", points: points)
        }
        let rejected = makeRepository(answering: 422, #"{ "error": { "code": "too_short", "message": "x", "details": [{ "field": "points", "message": "too_short" }, { "field": "points", "message": "loop" }] } }"#)
        await #expect(throws: SegmentCreationError.rejected([.tooShort, .loop])) {
            try await rejected.create(sport: .run, name: "Mon Semnoz", points: points)
        }
        let down = makeRepository(answering: 503, #"{ "error": { "code": "elevation_unavailable", "message": "x" } }"#)
        await #expect(throws: SegmentCreationError.unavailable) {
            try await down.preview(sport: .run, points: points)
        }
    }
}
