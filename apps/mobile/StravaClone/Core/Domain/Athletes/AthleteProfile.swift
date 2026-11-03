import Foundation

/// Where the viewer stands with an athlete (ADR-036 §1).
enum FollowStatus: String, Equatable, Sendable {
    case none
    case pending
    case accepted
}

/// An athlete's profile, as the viewer may see it (ADR-036 §3): every figure only counts the
/// Activities this viewer may see. Shared by the Profile tab and another athlete's profile.
struct AthleteProfile: Equatable, Sendable {
    var athlete: ActivityAuthor
    let activityCount: Int
    /// Consecutive weeks with an Activity, ending with the current week (ADR-036 §4).
    let streakWeeks: Int
    var followerCount: Int
    let followingCount: Int
    /// Nil on one's own profile.
    let viewerFollowStatus: FollowStatus?
    /// Up to 2 of the athlete's followers whom the viewer follows.
    let followersYouKnow: [ActivityAuthor]
    let practicedSports: [SportType]
    /// Own profile only: "Approuver mes abonnés".
    var approveFollowers: Bool?
    /// Own profile only.
    let pendingFollowRequestCount: Int?
    /// Own profile only: the number of Itineraries, for Plus.
    let itineraryCount: Int?

    var isOwn: Bool { viewerFollowStatus == nil }
}

/// Failures when reading or changing an athlete's profile, as the presentation needs them.
enum AthleteError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// The athlete does not exist (`404 athlete_not_found`).
    case notFound
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    case network
}

/// Reads any athlete's profile, Activities and statistics (ADR-036 §3, §4). Implemented over
/// the API in `Core/Athletes`, faked in tests.
protocol AthleteRepository: Sendable {
    func profile(of athleteId: String) async throws(AthleteError) -> AthleteProfile
    /// The athlete's visible processed Activities, newest first, as feed cards.
    func activities(of athleteId: String, cursor: String?) async throws(AthleteError) -> FeedPage
    /// "Cette année : X km": the distance since 1 January, all sports.
    func yearToDateDistance(of athleteId: String) async throws(AthleteError) -> Distance
}
