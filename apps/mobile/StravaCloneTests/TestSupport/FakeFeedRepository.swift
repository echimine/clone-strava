import Foundation
@testable import StravaClone

/// In-memory `FeedRepository` (ADR-025 §3): scripted pages and kudos answers, recorded calls.
final class FakeFeedRepository: FeedRepository, @unchecked Sendable {
    private let lock = NSLock()

    /// Answers keyed by cursor (`nil` = first page).
    var pages: [String?: Result<FeedPage, FeedError>] = [:]
    var kudosResult: Result<KudosState, FeedError>?
    /// Suspends `setKudos` until resumed, to observe the optimistic state.
    var kudosGate: AsyncStream<Void>?

    /// Answer of `recentKudos`; no givers by default.
    var recentKudosResult: Result<[ActivityAuthor], FeedError> = .success([])

    private(set) var requestedCursors: [String?] = []
    private(set) var recentKudosCalls: [ActivityID] = []
    private(set) var kudosCalls: [(given: Bool, id: ActivityID)] = []

    func page(cursor: String?) async throws(FeedError) -> FeedPage {
        let result = lock.withLock {
            requestedCursors.append(cursor)
            return pages[cursor] ?? .failure(.network)
        }
        return try result.get()
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(FeedError) -> KudosState {
        lock.withLock { kudosCalls.append((given, activityId)) }
        if let gate = kudosGate {
            for await _ in gate { break }
        }
        let result = lock.withLock { kudosResult } ?? .success(KudosState(kudosCount: given ? 1 : 0, viewerHasKudoed: given))
        return try result.get()
    }

    func recentKudos(activityId: ActivityID) async throws(FeedError) -> [ActivityAuthor] {
        let result = lock.withLock {
            recentKudosCalls.append(activityId)
            return recentKudosResult
        }
        return try result.get()
    }
}

/// `FeedEventSource` driven by the test.
final class FakeFeedEventSource: FeedEventSource, @unchecked Sendable {
    let stream: AsyncStream<Void>
    let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func activityChanges() async -> AsyncStream<Void> { stream }
}

extension ActivityPost {
    static func fixture(
        id: ActivityID = ActivityID(),
        title: String = "Sortie",
        sport: SportType = .run,
        kudos: Int = 0,
        comments: Int = 0,
        viewerHasKudoed: Bool = false,
        viewerIsAuthor: Bool = false,
        elevationGain: Double? = 120,
        avgSpeedMs: Double? = nil,
        routeTrimmed: Bool = false,
        recentKudos: [ActivityAuthor] = []
    ) -> ActivityPost {
        ActivityPost(
            id: id,
            title: title,
            sport: sport,
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            locationName: "Annecy, Haute-Savoie",
            distance: Distance(meters: 10_000),
            movingTime: .seconds(3_000),
            elevationGain: elevationGain,
            avgSpeedMs: avgSpeedMs,
            route: nil,
            routeTrimmed: routeTrimmed,
            author: ActivityAuthor(id: "u1", displayName: "Camille Martin", avatarURL: nil),
            engagement: ActivityEngagement(kudosCount: kudos, commentCount: comments, viewerHasKudoed: viewerHasKudoed),
            recentKudos: recentKudos,
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
