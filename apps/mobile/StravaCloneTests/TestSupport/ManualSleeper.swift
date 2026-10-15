import Foundation

/// A clock for scheduled wake-ups, driven by the test: each `sleep` waits until `wakeAll()` or
/// until its task is cancelled (then it throws, like `Task.sleep`).
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var _requested: [Duration] = []

    /// The delays asked for, in order.
    var requested: [Duration] { lock.withLock { _requested } }
    /// Sleeps still waiting (neither woken nor cancelled).
    var waiting: Int { lock.withLock { sleepers.count } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] delay in try await wait(delay) }
    }

    /// Every waiting sleep ends now.
    func wakeAll() {
        let woken = lock.withLock {
            defer { sleepers = [:] }
            return Array(sleepers.values)
        }
        for continuation in woken {
            continuation.resume()
        }
    }

    private func wait(_ delay: Duration) async throws {
        let key = UUID()
        lock.withLock { _requested.append(delay) }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelled = lock.withLock {
                    if Task.isCancelled { return true }
                    sleepers[key] = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation = lock.withLock { sleepers.removeValue(forKey: key) }
            continuation?.resume(throwing: CancellationError())
        }
    }
}
