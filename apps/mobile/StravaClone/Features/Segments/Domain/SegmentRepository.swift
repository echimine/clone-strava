import Foundation

/// The Segment sheet's reads and the creator's actions (ADR-039 §12). Renaming, deleting and
/// favourites are served by the endpoints of spec #249.
protocol SegmentRepository: Sendable {
    func sheet(id: String) async throws(SegmentError) -> SegmentSheet
    func leaderboard(id: String, selection: LeaderboardSelection, cursor: String?) async throws(SegmentError) -> Leaderboard
    func setFavorite(id: String, _ isFavorite: Bool) async throws(SegmentError)
    func rename(id: String, to name: String) async throws(SegmentError)
    func delete(id: String) async throws(SegmentError)
}
