import Foundation

/// A Segment's sheet (`GET /v1/segments/:id`, ADR-039 §12): free for everyone.
struct LoadSegmentSheet: Sendable {
    let repository: any SegmentRepository

    func callAsFunction(_ segmentID: String) async throws(SegmentError) -> SegmentSheet {
        try await repository.sheet(id: segmentID)
    }
}

/// One page of a Segment's Leaderboard for the chips selected (ADR-039 §8, §9); `cursor` nil is
/// the first page.
struct LoadLeaderboard: Sendable {
    let repository: any SegmentRepository

    func callAsFunction(
        _ segmentID: String,
        selection: LeaderboardSelection,
        cursor: String? = nil
    ) async throws(SegmentError) -> Leaderboard {
        try await repository.leaderboard(id: segmentID, selection: selection, cursor: cursor)
    }
}

/// « Renommer », for the Segment's creator (ADR-039 §5).
struct RenameSegment: Sendable {
    let repository: any SegmentRepository

    func callAsFunction(_ segmentID: String, to name: String) async throws(SegmentError) {
        try await repository.rename(id: segmentID, to: name)
    }
}

/// « Supprimer », for the Segment's creator while nobody else has an Effort on it (ADR-039 §5).
struct DeleteSegment: Sendable {
    let repository: any SegmentRepository

    func callAsFunction(_ segmentID: String) async throws(SegmentError) {
        try await repository.delete(id: segmentID)
    }
}
