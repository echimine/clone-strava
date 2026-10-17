import Foundation
@testable import StravaClone

/// In-memory realtime connection: records what the app sends, lets a test push server events
/// and (re)connections. `isConnected` false makes `send` fail like a closed socket.
final class FakeRealtimeChannel: RealtimeChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var eventContinuations: [AsyncStream<RealtimeEvent>.Continuation] = []
    private var connectionContinuations: [AsyncStream<Void>.Continuation] = []
    private var _sent: [String] = []
    private var _attempts = 0
    private var _isConnected = true

    /// Messages sent on an open connection.
    var sent: [String] { lock.withLock { _sent } }
    /// Every `send`, including those refused while disconnected.
    var attempts: Int { lock.withLock { _attempts } }

    var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    func events() async -> AsyncStream<RealtimeEvent> {
        let (stream, continuation) = AsyncStream<RealtimeEvent>.makeStream()
        lock.withLock { eventContinuations.append(continuation) }
        return stream
    }

    func connections() async -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { connectionContinuations.append(continuation) }
        return stream
    }

    func send(_ message: String) async -> Bool {
        lock.withLock {
            _attempts += 1
            guard _isConnected else { return false }
            _sent.append(message)
            return true
        }
    }

    /// A server event, as the gateway sends it.
    func push(type: String, id: String = UUID().uuidString, data: [String: String]) {
        let payload = try! JSONSerialization.data(withJSONObject: data)
        let event = RealtimeEvent(type: type, id: id, data: payload)
        for continuation in lock.withLock({ eventContinuations }) {
            continuation.yield(event)
        }
    }

    /// The connection came (back) up.
    func reconnect() {
        isConnected = true
        for continuation in lock.withLock({ connectionContinuations }) {
            continuation.yield()
        }
    }
}

/// Answers `POST /v1/realtime/grants` with "grant-1", "grant-2"… and records the topics asked.
final class FakeRealtimeGrants: @unchecked Sendable {
    private let lock = NSLock()
    private var _topics: [String] = []

    var topics: [String] { lock.withLock { _topics } }

    func grant(_ topic: String) async throws -> String {
        lock.withLock {
            _topics.append(topic)
            return "grant-\(_topics.count)"
        }
    }
}
