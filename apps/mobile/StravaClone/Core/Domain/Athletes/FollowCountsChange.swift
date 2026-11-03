import Foundation

/// How the viewer's own counters move after a follow change (ADR-036 §1): a follow request
/// accepted or refused, a follower removed, an athlete followed or unfollowed. In Core because
/// the follow screens make the change and the Profile tab's header shows the counters.
struct FollowCountsChange: Equatable, Sendable {
    var followers = 0
    var following = 0
    var pendingRequests = 0

    /// The viewer's following count moves only when they become, or stop being, an accepted
    /// follower: a request sent or cancelled changes nothing.
    static func following(from previous: FollowStatus, to new: FollowStatus) -> FollowCountsChange {
        FollowCountsChange(following: (new == .accepted ? 1 : 0) - (previous == .accepted ? 1 : 0))
    }

    var isEmpty: Bool { self == FollowCountsChange() }
}

extension AthleteProfile {
    mutating func apply(_ change: FollowCountsChange) {
        followerCount = max(0, followerCount + change.followers)
        followingCount = max(0, followingCount + change.following)
        pendingFollowRequestCount = pendingFollowRequestCount.map { max(0, $0 + change.pendingRequests) }
    }
}
