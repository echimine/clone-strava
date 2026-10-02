import Foundation

/// Author of an activity as shown to other users (ADR-029).
struct ActivityAuthor: Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarURL: URL?
}

/// Kudos and comments of an activity (ADR-029). `viewerHasKudoed` is about the signed-in user.
struct ActivityEngagement: Hashable, Sendable {
    var kudosCount: Int
    var commentCount: Int
    var viewerHasKudoed: Bool

    /// Optimistic local update of a kudos tap, reconciled with the server's answer afterwards.
    func togglingKudos() -> ActivityEngagement {
        ActivityEngagement(
            kudosCount: max(0, kudosCount + (viewerHasKudoed ? -1 : 1)),
            commentCount: commentCount,
            viewerHasKudoed: !viewerHasKudoed
        )
    }
}

/// An activity as listed in a feed or on a profile (ADR-029): what an `ActivityCard` shows.
/// Lives in Core because Feed and Profile both list activities (ADR-007 rule 5).
struct ActivityPost: Identifiable, Hashable, Sendable {
    let id: ActivityID
    let title: String
    let sport: SportType
    let startedAt: Date
    let locationName: String?
    let distance: Distance?
    let movingTime: Duration?
    let elevationGain: Double?
    let route: EncodedPolyline?
    let author: ActivityAuthor
    var engagement: ActivityEngagement
    let viewerIsAuthor: Bool
}
