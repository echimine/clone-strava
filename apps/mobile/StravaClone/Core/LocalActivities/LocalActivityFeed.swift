import Foundation

/// `LocalActivityFeedSource` over GRDB and `ActivitySender` (ADR-031 §14, §15): the feed reads
/// the cards from the store; Delete and Retry go through the sender, which sends what they
/// queue right away.
@MainActor
struct LocalActivityFeed: LocalActivityFeedSource {
    let store: GRDBLocalActivityStore
    let sender: ActivitySender

    func cards() -> AsyncStream<[LocalActivityCard]> {
        store.observeCards()
    }

    func delete(_ id: ActivityID) async throws {
        try await sender.delete(id)
    }

    func retry(_ id: ActivityID) async throws {
        try await sender.retry(id)
    }

    func deletionRefusals() -> AsyncStream<ActivityID> {
        sender.deletionRefusals()
    }
}
