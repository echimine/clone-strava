import Foundation

/// Where the viewer stands with an athlete after following or unfollowing them (ADR-036 §1).
struct FollowChange: Equatable, Sendable {
    let athleteId: String
    let status: FollowStatus
    /// The athlete's accepted followers, after the change.
    let followerCount: Int
}

/// Following and unfollowing an athlete (ADR-036 §1). Implemented over the API in
/// `Infrastructure`, faked in tests.
protocol FollowRepository: Sendable {
    /// Follows, or asks to when the athlete approves their followers. Idempotent.
    func follow(_ athleteId: String) async throws(AthleteError) -> FollowChange
    /// Unfollows, or cancels a pending request. Idempotent.
    func unfollow(_ athleteId: String) async throws(AthleteError) -> FollowChange
}
