import Foundation

/// `ActivityLiveEventSource` on the shared realtime connection (ADR-034 §5): the token only
/// covers `user:{id}`, so the detail asks a grant for `activity:{id}` and sends `sub` with it.
///
/// The subscription also brings `activity.updated` / `activity.deleted` onto the connection:
/// the detail store already follows them (`ActivityEventSource`, ADR-033 §8), so they are not
/// repeated here; a deletion only ends the subscription.
struct RealtimeActivityLiveEventSource: ActivityLiveEventSource {
    typealias Grant = @Sendable (_ topic: String) async throws -> String

    let channel: any RealtimeChannel
    /// `POST /v1/realtime/grants`, asked right before each `sub`: a grant lives 60 s.
    let grant: Grant

    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent> {
        let topic = realtimeActivityTopic(activityId)
        let channel = channel
        let grant = grant
        return AsyncStream { continuation in
            let task = Task {
                // Listening first: nothing arriving during the first `sub` is missed.
                let events = await channel.events()
                let connections = await channel.connections()
                await Self.subscribe(topic, on: channel, grant: grant)
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
                            await Self.subscribe(topic, on: channel, grant: grant)
                            continuation.yield(.reconnected)
                        }
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { _ = await channel.send(RealtimeControlMessage.unsubscribe(topic: topic)) }
            }
        }
    }

    /// A failure (offline, Activity no longer visible) only means no live events until the next
    /// connection: the detail itself shows what the API answers.
    private static func subscribe(_ topic: String, on channel: any RealtimeChannel, grant: Grant) async {
        guard let grant = try? await grant(topic) else { return }
        _ = await channel.send(RealtimeControlMessage.subscribe(topic: topic, grant: grant))
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
