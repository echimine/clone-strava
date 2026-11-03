import Foundation

/// Opens an athlete's followers and following lists (ADR-036 §1, §10) from their counters. In
/// Core because both the Profile tab and another athlete's profile open them; each tab's
/// `NavigationStack` that shows a profile registers it. Carries the counters the lists start
/// from, since the lists themselves have no total.
struct AthleteFollowsRequest: Hashable, Sendable {
    /// Which of the two lists.
    enum Kind: Hashable, Sendable, CaseIterable {
        case followers, following
    }

    let athleteId: String
    /// The lists' title.
    let athleteName: String
    /// The list shown first.
    let list: Kind
    /// The viewer's own lists: the "Demandes d'abonnement" row and removing a follower.
    let isOwn: Bool
    let followerCount: Int
    let followingCount: Int
    /// Own lists only.
    let pendingRequestCount: Int

    init(profile: AthleteProfile, list: Kind) {
        athleteId = profile.athlete.id
        athleteName = profile.athlete.displayName
        self.list = list
        isOwn = profile.isOwn
        followerCount = profile.followerCount
        followingCount = profile.followingCount
        pendingRequestCount = profile.isOwn ? profile.pendingFollowRequestCount ?? 0 : 0
    }
}
