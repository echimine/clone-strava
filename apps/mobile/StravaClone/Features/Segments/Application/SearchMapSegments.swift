import Foundation

/// The Segments of the Map's zone, the most-ridden first (`GET /v1/segments`, ADR-039 §12).
struct SearchMapSegments: Sendable {
    let repository: any SegmentMapRepository

    func callAsFunction(in area: MapArea, filter: SegmentMapFilter) async throws(SegmentError) -> [MapSegment] {
        try await repository.segments(in: area, filter: filter)
    }
}
