import Foundation

/// `FeedEventSource` on top of the shared realtime connection: an activity of the user
/// finished processing (`activity.processed`, ADR-010), so the feed has a new card.
/// `activity_import.completed` is not enough: the activity is still processing then (ADR-029).
struct RealtimeFeedEventSource: FeedEventSource {
    let client: WebSocketClient

    func activityChanges() async -> AsyncStream<Void> {
        let realtime = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in realtime where event.type == "activity.processed" {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
