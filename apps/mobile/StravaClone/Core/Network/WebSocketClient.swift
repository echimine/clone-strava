import Foundation

/// Realtime client over URLSessionWebSocketTask (ADR-006, protocol in ADR-010).
/// Open in the foreground only; the WS is never the source of truth (ADR-001).
actor WebSocketClient {
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<Data>.Continuation?

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Opens the connection with a short-lived realtime token and returns the raw
    /// `{ v, t, id, data }` messages. Features decode and filter the events they need.
    func connect(token: String) -> AsyncStream<Data> {
        disconnect()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        self.task = task

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.continuation = continuation
        task.resume()
        Task { await receiveLoop(task) }

        // TODO(ADR-006): subscribe to `user:{userId}` with { "a": "sub", "topic": ... }.
        // TODO(ADR-006): heartbeat, { "a": "ping" } every 25 s to detect a dead connection.
        // TODO(ADR-006): reconnection with exponential backoff and a new token every time,
        //   reacting to close codes 4001 (invalid token), 4008 (quota), 4009 (server restart).
        // TODO(ADR-006): deduplicate events by `id`, then resync through the API after reconnecting.
        return stream
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while self.task === task {
            do {
                switch try await task.receive() {
                case .data(let data):
                    continuation?.yield(data)
                case .string(let text):
                    continuation?.yield(Data(text.utf8))
                @unknown default:
                    break
                }
            } catch {
                if self.task === task { disconnect() }
                return
            }
        }
    }
}
