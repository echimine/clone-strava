import Foundation

/// `ImportEventSource` on top of the shared realtime connection: keeps only
/// `activity_import.completed` / `activity_import.failed` (ADR-028 §10).
struct RealtimeImportEventSource: ImportEventSource {
    let client: WebSocketClient

    private struct Payload: Decodable {
        let importId: UUID
    }

    func events() async -> AsyncStream<ImportEvent> {
        let realtime = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in realtime {
                    guard let payload = event.payload(as: Payload.self) else { continue }
                    switch event.type {
                    case "activity_import.completed": continuation.yield(.completed(importId: payload.importId))
                    case "activity_import.failed": continuation.yield(.failed(importId: payload.importId))
                    default: continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
