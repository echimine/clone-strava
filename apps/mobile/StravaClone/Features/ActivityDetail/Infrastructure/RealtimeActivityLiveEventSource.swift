import Foundation

/// `ActivityLiveEventSource` on the shared realtime connection (ADR-034 §5): the token only
/// covers `user:{id}`, so the detail asks a grant for `activity:{id}` and sends `sub` with it.
///
/// The subscription also brings `activity.updated` / `activity.deleted` onto the connection:
/// the detail store already follows them (`ActivityEventSource`, ADR-033 §8), so they are not
/// repeated here; a deletion only ends the subscription.
///
/// One instance for the app: streams of the same Activity (the detail and the Kudos and
/// comments screen pushed over it) share one subscription (`RealtimeTopicSubscriptions`).
struct RealtimeActivityLiveEventSource: ActivityLiveEventSource {
    typealias Grant = RealtimeTopicSubscriptions.Grant

    let channel: any RealtimeChannel
    let subscriptions: RealtimeTopicSubscriptions

    /// `grant`: `POST /v1/realtime/grants`, asked right before each `sub`.
    init(channel: any RealtimeChannel, grant: @escaping Grant) {
        self.channel = channel
        subscriptions = RealtimeTopicSubscriptions(channel: channel, grant: grant)
    }

    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent> {
        let topic = realtimeActivityTopic(activityId)
        let channel = channel
        let subscriptions = subscriptions
        return AsyncStream { continuation in
            let task = Task {
                // Listening first: nothing arriving during the first `sub` is missed.
                let events = await channel.events()
                let connections = await channel.connections()
                await subscriptions.acquire(topic)
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await event in events {
                            guard let payload = Self.payload(of: event, about: activityId) else { continue }
                            if event.type == "activity.deleted" {
                                continuation.finish() // unsubscribes
                                return
                            }
                            if let event = Self.liveEvent(event.type, payload) {
                                continuation.yield(event)
                            }
                        }
                    }
                    group.addTask {
                        for await _ in connections {
                            await subscriptions.resubscribe(topic)
                            continuation.yield(.reconnected)
                        }
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await subscriptions.release(topic) }
            }
        }
    }

    /// `data` of the `activity:{id}` events (`packages/realtime/src/events.ts`).
    private struct Payload: Decodable {
        let activityId: String
        let commentId: String?
    }

    /// The connection also carries `user:{id}` (other Activities of the viewer, imports…): only
    /// this Activity's events count. The author gets `activity.*` on both topics with the same
    /// envelope id: `WebSocketClient` already drops the copy.
    private static func payload(of event: RealtimeEvent, about activityId: ActivityID) -> Payload? {
        guard let payload = event.payload(as: Payload.self),
              UUID(uuidString: payload.activityId) == activityId.rawValue else { return nil }
        return payload
    }

    private static func liveEvent(_ type: String, _ payload: Payload) -> ActivityLiveEvent? {
        let commentId = payload.commentId.flatMap(UUID.init(uuidString:))
        switch (type, commentId) {
        case ("comment.created", let id?): return .commentCreated(id)
        case ("comment.updated", let id?): return .commentUpdated(id)
        case ("comment.deleted", let id?): return .commentDeleted(id)
        case ("kudos.changed", _): return .kudosChanged
        default: return nil
        }
    }
}
