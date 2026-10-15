import Foundation

/// The status line of a local Activity's card (ADR-031 §14).
enum LocalActivityStatus: Equatable, Sendable {
    /// The last attempt found no network.
    case waitingForNetwork
    /// On its way (or about to be).
    case sending
    /// The server could not take it (`5xx`, session): tried again after a delay.
    case retryingSoon
    /// Handed to the worker.
    case processing
    /// Refused by the API or failed by the worker, with the server's code.
    case failed(reason: String)
}

/// One local Activity on top of the feed (ADR-031 §14): provisional values, a route drawn from
/// the local points (polyline5 of at most 2,000 characters, no privacy zone: only the author
/// sees it) and a status line. No elevation gain, place, kudos, comments or share.
struct LocalActivityCard: Identifiable, Equatable, Sendable {
    let activity: LocalActivity
    let status: LocalActivityStatus
    /// nil with fewer than 2 points.
    let route: EncodedPolyline?

    var id: ActivityID { activity.id }
}

/// What the feed sees of the local Activities (ADR-031 §14, §15), implemented by
/// `Core/LocalActivities`: the cards as they change, Delete and Retry.
@MainActor
protocol LocalActivityFeedSource {
    /// The current cards, newest first, then again after each change.
    func cards() -> AsyncStream<[LocalActivityCard]>
    /// Throws `LocalActivityActionError.notAllowed` once `processing`.
    func delete(_ id: ActivityID) async throws
    /// Throws `LocalActivityActionError.notAllowed` unless refused by the API.
    func retry(_ id: ActivityID) async throws
    /// Deletes the server turned down (`409`: already handed to the worker), as they happen:
    /// the Activity is back in `processing`.
    func deletionRefusals() -> AsyncStream<ActivityID>
}
