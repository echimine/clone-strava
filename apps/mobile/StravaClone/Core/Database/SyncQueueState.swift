import Foundation
import GRDB

/// How many operations wait in `sync_operation`, whatever the feature (ADR-031 §14): the
/// background refresh is scheduled only while there is at least one.
struct SyncQueueState: Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func pendingCount() async -> Int {
        (try? await database.writer.read { db in try SyncOperationRecord.fetchCount(db) }) ?? 0
    }

    /// The current count, then again each time it changes. Runs until cancelled.
    func pendingCounts() -> AsyncStream<Int> {
        let observation = ValueObservation.tracking { db in try SyncOperationRecord.fetchCount(db) }.removeDuplicates()
        let writer = database.writer
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await count in observation.values(in: writer) {
                        continuation.yield(count)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
