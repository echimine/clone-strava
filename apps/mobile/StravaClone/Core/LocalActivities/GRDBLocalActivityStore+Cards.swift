import Foundation
import GRDB

/// The feed side of the local Activities (ADR-031 §14): one card per local Activity, newest
/// first, with its status line and a route drawn from its points. An Activity waiting for the
/// server to confirm its Delete has no card.
extension GRDBLocalActivityStore {
    func cards() async throws -> [LocalActivityCard] {
        try await database.writer.read(Self.fetchCards)
    }

    /// The cards, then again after each change of `local_activity` or `sync_operation`. Points
    /// written by a Recording in progress do not wake it up.
    func observeCards() -> AsyncStream<[LocalActivityCard]> {
        let observation = ValueObservation
            .tracking(regions: [Table(LocalActivityRow.databaseTableName), Table(SyncOperationRecord.databaseTableName)], fetch: Self.fetchCards)
            .removeDuplicates()
        let writer = database.writer
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await cards in observation.values(in: writer) {
                        continuation.yield(cards)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The status line from the state and the queued step: a step not tried yet is on its way,
    /// one that found no network waits for it, any other temporary failure is tried again soon.
    static func status(of activity: LocalActivity, operation: PendingActivityOperation?) -> LocalActivityStatus {
        switch activity.state {
        case .processing:
            return .processing
        case .failed:
            return .failed(reason: activity.failure?.reason ?? "processing_error")
        case .recorded, .created, .traceUploaded:
            guard let operation, operation.attempts > 0 else { return .sending }
            return operation.lastError == "\(ActivityServerError.offline)" ? .waitingForNetwork : .retryingSoon
        }
    }

    @Sendable
    private static func fetchCards(_ db: Database) throws -> [LocalActivityCard] {
        try LocalActivityRow
            .filter(!beingDeleted.contains(Column("id")))
            .order(Column("started_at_ms").desc)
            .fetchAll(db)
            .compactMap(\.activity)
            .map { activity in
            let coordinates = try Row.fetchAll(db, sql: """
                SELECT latitude, longitude FROM activity_point WHERE activity_id = ? ORDER BY timestamp_ms, id
                """, arguments: [activity.id.description]).map { Coordinate(latitude: $0["latitude"], longitude: $0["longitude"]) }
            return LocalActivityCard(
                activity: activity,
                status: status(of: activity, operation: try operation(for: activity.id, db)),
                route: coordinates.count >= 2 ? EncodedPolyline.thumbnail(of: coordinates) : nil
            )
        }
    }
}
