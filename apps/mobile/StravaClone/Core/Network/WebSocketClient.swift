import Foundation

/// Realtime client over URLSessionWebSocketTask (ADR-006, protocol in ADR-010).
/// Open in the foreground only; the WS is never the source of truth (ADR-001): a missed
/// event is caught up by reloading through the API.
///
/// - Every (re)connection fetches a new short-lived token, then subscribes to its topics.
/// - `{"a":"ping"}` every 25 s keeps the connection alive and detects a dead one.
/// - Reconnection with exponential backoff (1 s → 30 s) on any close or error, which
///   covers close codes 4001 (token), 4008 (quota) and 4009 (server restart).
/// - Events are deduplicated by `id` and fanned out to every `events()` subscriber.
actor WebSocketClient {
    typealias TokenSource = @Sendable () async throws -> String

    private static let pingInterval: Duration = .seconds(25)
    private static let maxBackoffSeconds = 30.0

    private let url: URL
    private let session: URLSession
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var subscribers: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    private var deduplicator = RealtimeEventDeduplicator()

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Connects (or reconnects with new topics) and keeps the connection up until `stop()`.
    func start(topics: [String], token: @escaping TokenSource) {
        stop()
        runTask = Task { await self.run(topics: topics, token: token) }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Stream of server events. Stays open across reconnections; ends when the caller
    /// stops iterating.
    func events() -> AsyncStream<RealtimeEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RealtimeEvent>.makeStream(bufferingPolicy: .bufferingNewest(50))
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func run(topics: [String], token: TokenSource) async {
        var failures = 0
        while !Task.isCancelled {
            do {
                let socket = session.webSocketTask(with: try await request(token: token))
                self.socket = socket
                socket.resume()
                for topic in topics {
                    try await socket.send(.string(RealtimeControlMessage.subscribe(topic: topic)))
                }
                failures = 0
                let pinger = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: Self.pingInterval)
                        try? await socket.send(.string(RealtimeControlMessage.ping))
                    }
                }
                defer { pinger.cancel() }
                while !Task.isCancelled {
                    receive(try await socket.receive())
                }
            } catch {
                // Closed, refused or token failure: fall through to the backoff below.
            }
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            if Task.isCancelled { return }
            failures += 1
            let delay = min(Self.maxBackoffSeconds, pow(2, Double(failures - 1)))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func request(token: TokenSource) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func receive(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let bytes): data = bytes
        case .string(let text): data = Data(text.utf8)
        @unknown default: return
        }
        guard let event = RealtimeEvent.decode(data), deduplicator.accept(event.id) else { return }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
}
