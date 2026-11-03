import Foundation

/// Topics outside the connection token (`activity:{id}`, ADR-034 §5), shared by every screen of
/// the shared connection. The gateway keeps one subscription per topic and connection, with no
/// count: two screens on the same topic (the detail, then the Kudos and comments screen pushed
/// over it, ADR-036 §8) must not let the first one to close unsubscribe the other. The first
/// holder sends `sub`, the last one `unsub`.
actor RealtimeTopicSubscriptions {
    typealias Grant = @Sendable (_ topic: String) async throws -> String

    private let channel: any RealtimeChannel
    /// `POST /v1/realtime/grants`, asked right before each `sub`: a grant lives 60 s.
    private let grant: Grant
    private var holders: [String: Int] = [:]

    init(channel: any RealtimeChannel, grant: @escaping Grant) {
        self.channel = channel
        self.grant = grant
    }

    /// How many screens hold `topic`.
    func holders(of topic: String) -> Int {
        holders[topic] ?? 0
    }

    /// A screen starts listening: the first one subscribes.
    func acquire(_ topic: String) async {
        let count = holders[topic, default: 0] + 1
        holders[topic] = count
        if count == 1 {
            await subscribe(topic)
        }
    }

    /// A screen stops listening: the last one unsubscribes.
    func release(_ topic: String) async {
        guard let count = holders[topic] else { return }
        guard count == 1 else {
            holders[topic] = count - 1
            return
        }
        holders[topic] = nil
        _ = await channel.send(RealtimeControlMessage.unsubscribe(topic: topic))
    }

    /// After a reconnection: the gateway forgot the connection's topics, so a topic still held
    /// is subscribed again with a fresh grant.
    func resubscribe(_ topic: String) async {
        guard holders[topic] != nil else { return }
        await subscribe(topic)
    }

    /// A failure (offline, Activity no longer visible) only means no live events until the next
    /// connection. A topic released while its grant was on its way is not subscribed.
    private func subscribe(_ topic: String) async {
        guard let grant = try? await grant(topic), holders[topic] != nil else { return }
        _ = await channel.send(RealtimeControlMessage.subscribe(topic: topic, grant: grant))
    }
}
