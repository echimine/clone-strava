import Foundation

enum SegmentError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// Deleted: « Ce Segment n'est plus disponible ».
    case notFound
    /// A filter, a sex or a page without Premium (ADR-039 §9).
    case premiumRequired
    /// « Supprimer » refused: someone else has an Effort on it (ADR-039 §5).
    case hasOtherEfforts
    case invalid(code: String?)
    case server
    case network
}

/// The Segment sheet's reads and the creator's actions (ADR-039 §12). Renaming, deleting and
/// starring are served by the endpoints of spec #249.
protocol SegmentRepository: Sendable {
    func sheet(id: String) async throws(SegmentError) -> SegmentSheet
    func leaderboard(id: String, selection: LeaderboardSelection, cursor: String?) async throws(SegmentError) -> Leaderboard
    func setStarred(id: String, _ starred: Bool) async throws(SegmentError)
    func rename(id: String, to name: String) async throws(SegmentError)
    func delete(id: String) async throws(SegmentError)
}
