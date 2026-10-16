import Foundation

/// `ActivityEventSource` on top of the shared realtime connection (ADR-010): keeps only
/// `activity.updated` `{ activityId, changedFields }` (ADR-033 §8). The echo of the device's own
/// edit comes too; reloading is harmless.
struct RealtimeActivityEventSource: ActivityEventSource {
    let client: WebSocketClient

    func activityEvents() async -> AsyncStream<ActivityEvent> {
        let realtime = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in realtime {
                    if let event = Self.event(from: event) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private struct Payload: Decodable {
        let activityId: String
    }

    /// The Activity event a realtime message carries; nil for any other or unreadable one.
    static func event(from event: RealtimeEvent) -> ActivityEvent? {
        guard let payload = event.payload(as: Payload.self),
              let uuid = UUID(uuidString: payload.activityId) else {
            return nil
        }
        switch event.type {
        case "activity.updated": return .updated(ActivityID(uuid))
        default: return nil
        }
    }
}
