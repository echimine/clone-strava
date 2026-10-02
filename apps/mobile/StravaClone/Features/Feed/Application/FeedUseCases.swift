import Foundation

/// Loads one page of the feed (ADR-007 `LoadFeed`).
struct LoadFeed: Sendable {
    let repository: any FeedRepository

    func callAsFunction(cursor: String? = nil) async throws(FeedError) -> FeedPage {
        try await repository.page(cursor: cursor)
    }
}

/// Gives or removes kudos on an activity (ADR-029).
struct ToggleKudos: Sendable {
    let repository: any FeedRepository

    func callAsFunction(_ given: Bool, activityId: ActivityID) async throws(FeedError) -> KudosState {
        try await repository.setKudos(given, activityId: activityId)
    }
}
