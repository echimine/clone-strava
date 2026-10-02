import Foundation

/// One page of the feed (ADR-029): `nextCursor` is nil on the last page.
struct FeedPage: Equatable, Sendable {
    let posts: [ActivityPost]
    let nextCursor: String?
}

/// Kudos of one activity as the server sees it after a give/remove (ADR-029).
struct KudosState: Equatable, Sendable {
    let kudosCount: Int
    let viewerHasKudoed: Bool
}

/// Failures of the feed, as the presentation needs them.
enum FeedError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// The activity is gone or no longer visible (`404`).
    case notFound
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    case network
}

/// Feed port (ADR-007): implemented over the API in Infrastructure, faked in tests.
protocol FeedRepository: Sendable {
    func page(cursor: String?) async throws(FeedError) -> FeedPage
    /// Gives (`true`) or removes (`false`) kudos; returns the server's state.
    func setKudos(_ given: Bool, activityId: ActivityID) async throws(FeedError) -> KudosState
}

/// Signals that the signed-in user's activities changed (e.g. `activity.processed`, ADR-010).
protocol FeedEventSource: Sendable {
    func activityChanges() async -> AsyncStream<Void>
}
