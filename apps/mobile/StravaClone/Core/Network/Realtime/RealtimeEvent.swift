import Foundation

/// A server event of the realtime protocol (ADR-010 §5, `packages/realtime/src/protocol.ts`):
/// `{ "v": 1, "t": "activity.processed", "id": "evt_…", "data": { … } }`.
/// `data` is kept as raw JSON: each feature decodes only the events it cares about.
struct RealtimeEvent: Equatable, Sendable {
    let type: String
    let id: String
    let data: Data

    static let protocolVersion = 1

    /// Decodes one WebSocket message. Returns `nil` for control messages (`sub:ok`,
    /// `pong`…), unknown protocol versions and unreadable payloads: an unknown message
    /// is ignored, never an error (ADR-010 §5).
    static func decode(_ message: Data) -> RealtimeEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
            object["v"] as? Int == protocolVersion,
            let type = object["t"] as? String,
            let id = object["id"] as? String,
            let payload = object["data"] as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: payload)
        else {
            return nil
        }
        return RealtimeEvent(type: type, id: id, data: data)
    }

    /// Decodes `data` into a feature's own payload type.
    func payload<T: Decodable>(as type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

/// Client → server control messages (ADR-010 §5).
enum RealtimeControlMessage {
    static func subscribe(topic: String) -> String {
        encode(["a": "sub", "topic": topic])
    }

    /// A topic outside the connection token, with its grant (`POST /v1/realtime/grants`, ADR-034 §5).
    static func subscribe(topic: String, grant: String) -> String {
        encode(["a": "sub", "topic": topic, "grant": grant])
    }

    static func unsubscribe(topic: String) -> String {
        encode(["a": "unsub", "topic": topic])
    }

    static let ping = encode(["a": "ping"])

    private static func encode(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Remembers the last event ids to drop duplicates (ADR-010 §5 "id: to ignore a duplicate
/// on the client side"), e.g. after a reconnection replays an event. Bounded memory.
struct RealtimeEventDeduplicator {
    private var seen: Set<String> = []
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    /// `true` the first time an id is seen.
    mutating func accept(_ id: String) -> Bool {
        guard seen.insert(id).inserted else { return false }
        order.append(id)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }
}

/// `user:{userId}` topic (ADR-010 §4), the only one granted by the realtime token in the MVP.
func realtimeUserTopic(_ userId: String) -> String {
    "user:\(userId)"
}

/// `activity:{id}` topic (ADR-034 §5): an open detail, subscribed with a grant. The id is
/// lowercase, as the API stores it: the gateway compares topics exactly.
func realtimeActivityTopic(_ id: ActivityID) -> String {
    "activity:\(id)"
}
