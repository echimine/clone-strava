import Foundation

/// Measures a drawn path as the server would store it, and says what would refuse it
/// (`POST /v1/segments/preview`, ADR-039 §5, §12).
struct PreviewSegment: Sendable {
    let repository: any SegmentCreationRepository

    func callAsFunction(sport: SegmentSport, points: [Coordinate]) async throws(SegmentError) -> SegmentPreview {
        try await repository.preview(sport: sport, points: points)
    }
}

/// « Créer le Segment » (`POST /v1/segments`, ADR-039 §5): the server resamples the drawn path
/// again and starts looking for past Efforts on it.
struct CreateSegment: Sendable {
    let repository: any SegmentCreationRepository

    func callAsFunction(sport: SegmentSport, name: String, points: [Coordinate]) async throws(SegmentError) -> SegmentRef {
        try await repository.create(sport: sport, name: name, points: points)
    }
}
