import Foundation

/// Owns the app's realtime connection (ADR-010): opened while a user is signed in and the
/// app is in the foreground (ADR-001), on the user's own topic. Features read
/// `events()` and filter the types they need.
@MainActor
final class RealtimeService {
    private let client: WebSocketClient
    private let tokenProvider: RealtimeTokenProvider
    private var connectedUserId: String?

    init(client: WebSocketClient, tokenProvider: RealtimeTokenProvider) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func connect(userId: String) async {
        guard connectedUserId != userId else { return }
        connectedUserId = userId
        let tokenProvider = tokenProvider
        await client.start(topics: [realtimeUserTopic(userId)]) {
            try await tokenProvider.token()
        }
    }

    func disconnect() async {
        connectedUserId = nil
        await client.stop()
    }

    func events() async -> AsyncStream<RealtimeEvent> {
        await client.events()
    }
}
