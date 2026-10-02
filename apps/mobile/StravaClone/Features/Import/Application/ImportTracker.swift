import Foundation

/// Waits for an import to reach a final status (ADR-028 §2). The realtime event
/// `activity_import.*` triggers an immediate reload; polling every `pollInterval`
/// covers a missing or broken WebSocket. Returns `nil` after `timeout`, when the
/// import is still being processed.
struct ImportTracker: Sendable {
    let repository: ActivityImportRepository
    let events: ImportEventSource
    var pollInterval: Duration = .seconds(2)
    var timeout: Duration = .seconds(120)

    private enum Signal: Sendable {
        case result(ActivityImport)
        case timedOut
        case streamEnded
    }

    func waitForFinalStatus(id: UUID) async -> ActivityImport? {
        let stream = await events.events()
        let repository = repository
        let pollInterval = pollInterval
        let timeout = timeout

        return await withTaskGroup(of: Signal.self) { group in
            group.addTask {
                for await event in stream where event.importId == id {
                    if let current = try? await repository.fetch(id: id), current.status.isFinal {
                        return .result(current)
                    }
                }
                return .streamEnded
            }
            group.addTask {
                while !Task.isCancelled {
                    if let current = try? await repository.fetch(id: id), current.status.isFinal {
                        return .result(current)
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                return .streamEnded
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }

            defer { group.cancelAll() }
            for await signal in group {
                switch signal {
                case .result(let finished): return finished
                case .timedOut: return nil
                case .streamEnded: continue
                }
            }
            return nil
        }
    }
}
