import Foundation
@testable import StravaClone

/// `LocalActivityFeedSource` driven by the test: cards pushed with `send`, actions recorded,
/// `actionError` thrown by Delete and Retry when set.
@MainActor
final class FakeLocalActivityFeedSource: LocalActivityFeedSource {
    private let stream: AsyncStream<[LocalActivityCard]>
    private let continuation: AsyncStream<[LocalActivityCard]>.Continuation
    private let refusals: AsyncStream<ActivityID>
    private let refusalContinuation: AsyncStream<ActivityID>.Continuation
    private(set) var deleted: [ActivityID] = []
    private(set) var retried: [ActivityID] = []
    var actionError: (any Error)?

    init() {
        (stream, continuation) = AsyncStream.makeStream()
        (refusals, refusalContinuation) = AsyncStream.makeStream()
    }

    /// The server answered `409` to the delete of `id`.
    func refuseDeletion(of id: ActivityID) {
        refusalContinuation.yield(id)
    }

    func deletionRefusals() -> AsyncStream<ActivityID> { refusals }

    func send(_ cards: [LocalActivityCard]) {
        continuation.yield(cards)
    }

    func cards() -> AsyncStream<[LocalActivityCard]> { stream }

    func delete(_ id: ActivityID) async throws {
        if let actionError { throw actionError }
        deleted.append(id)
    }

    func retry(_ id: ActivityID) async throws {
        if let actionError { throw actionError }
        retried.append(id)
    }
}

extension LocalActivityCard {
    static func fixture(
        id: ActivityID = ActivityID(),
        status: LocalActivityStatus = .waitingForNetwork,
        state: LocalActivityState = .recorded
    ) -> LocalActivityCard {
        LocalActivityCard(
            activity: LocalActivity(
                id: id,
                sport: .run,
                title: "Course à pied le matin",
                visibility: .public,
                startedAt: Date(timeIntervalSince1970: 1_792_047_600),
                endedAt: Date(timeIntervalSince1970: 1_792_048_200),
                distance: Distance(meters: 1_500),
                movingTimeS: 540,
                elapsedTimeS: 600,
                state: state
            ),
            status: status,
            route: nil
        )
    }
}
