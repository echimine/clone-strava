import Foundation

/// A page of a followers or following list (ADR-036 §1): most recent first.
struct AthleteListPage: Equatable, Sendable {
    let items: [AthleteListItem]
    let nextCursor: String?
}

/// Someone asking to follow the viewer, who approves their followers (ADR-036 §1).
struct FollowRequest: Equatable, Sendable, Identifiable {
    let athlete: ActivityAuthor
    /// Whether the viewer follows them.
    let viewerFollowStatus: FollowStatus?
    let requestedAt: Date

    var id: String { athlete.id }
}

struct FollowRequestPage: Equatable, Sendable {
    let items: [FollowRequest]
    let nextCursor: String?
}

/// The followers and following lists, the viewer's follow requests and followers (ADR-036 §1).
/// Implemented over the API in `Infrastructure`, faked in tests.
protocol FollowListRepository: Sendable {
    /// Accepted follows only; any athlete's lists.
    func list(_ list: AthleteFollowsRequest.Kind, of athleteId: String, cursor: String?) async throws(AthleteError) -> AthleteListPage
    func followRequests(cursor: String?) async throws(AthleteError) -> FollowRequestPage
    /// "Accepter": they become a follower.
    func acceptRequest(from followerId: String) async throws(AthleteError)
    /// "Refuser". Idempotent.
    func refuseRequest(from followerId: String) async throws(AthleteError)
    /// Removes one of the viewer's followers. Idempotent.
    func removeFollower(_ followerId: String) async throws(AthleteError)
}
