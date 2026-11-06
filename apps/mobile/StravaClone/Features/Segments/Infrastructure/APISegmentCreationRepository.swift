import Foundation

/// `APIClient` adapter of `SegmentCreationRepository`: `POST /v1/segments/preview` and
/// `POST /v1/segments` (ADR-039 §12).
struct APISegmentCreationRepository: SegmentCreationRepository {
    private struct Point: Encodable {
        let lat: Double
        let lon: Double
    }

    private struct PreviewBody: Encodable {
        let sport: String
        let points: [Point]
    }

    private struct CreateBody: Encodable {
        let sport: String
        let name: String
        let points: [Point]
    }

    private struct Ref: Decodable {
        let id: String
        let name: String
    }

    private struct Track: Decodable {
        let polyline6: String
        let altitudesM: [Double]
    }

    private struct PreviewAnswer: Decodable {
        let distanceM: Double
        let elevationGainM: Double
        let avgGradePct: Double
        let maxGradePct: Double
        let minAltitudeM: Double
        let maxAltitudeM: Double
        let climbCategory: String?
        let track: Track
        let violations: [String]
        let duplicate: Ref?
        let quotaLeft: Int
    }

    let apiClient: APIClient

    func preview(sport: SegmentSport, points: [Coordinate]) async throws(SegmentError) -> SegmentPreview {
        let body = PreviewBody(sport: sport.rawValue, points: points.map(Self.point))
        let answer: PreviewAnswer = try await SegmentAPIError.call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/segments/preview", body: body)
        }
        let track = EncodedPolyline(value: answer.track.polyline6, precision: 6).decode()
        return SegmentPreview(
            figures: SegmentFigures(
                distance: Distance(meters: answer.distanceM),
                elevationGain: answer.elevationGainM,
                averageGrade: answer.avgGradePct,
                maxGrade: answer.maxGradePct,
                lowestAltitude: answer.minAltitudeM,
                highestAltitude: answer.maxAltitudeM,
                climbCategory: answer.climbCategory.flatMap(ClimbCategory.init(rawValue:))
            ),
            track: track,
            altitudes: answer.track.altitudesM,
            violations: answer.violations.compactMap(SegmentRuleViolation.init(rawValue:)),
            duplicate: answer.duplicate.map { SegmentRef(id: $0.id, name: $0.name) },
            quotaLeft: answer.quotaLeft
        )
    }

    func create(sport: SegmentSport, name: String, points: [Coordinate]) async throws(SegmentError) -> SegmentRef {
        let body = CreateBody(sport: sport.rawValue, name: name, points: points.map(Self.point))
        let answer: Ref = try await SegmentAPIError.call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/segments", body: body)
        }
        return SegmentRef(id: answer.id, name: answer.name)
    }

    private static func point(_ coordinate: Coordinate) -> Point {
        Point(lat: coordinate.latitude, lon: coordinate.longitude)
    }
}
