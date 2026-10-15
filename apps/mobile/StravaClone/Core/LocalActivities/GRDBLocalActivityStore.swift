import Foundation
import GRDB

/// Local Activities in GRDB (ADR-031 §14, §15, migration `local_activities_v1`): the
/// `local_activity` rows, their `activity_point` / `activity_pause` rows (written by the
/// Recording under the same UUID) and their `sync_operation` rows. Every state change and its
/// operation are written in one transaction, so the order of the steps holds by construction.
struct GRDBLocalActivityStore: LocalActivitySaving {
    let database: AppDatabase
    var now: @Sendable () -> Date = Date.init

    // MARK: - Save (ADR-031 §11)

    /// One transaction: the local Activity in `recorded`, `create_activity` queued, the
    /// `recording` row deleted (its open final Pause with it). Killed before the commit, the
    /// finish screen comes back.
    func saveRecorded(_ activity: LocalActivity) async throws {
        let now = now()
        try await database.writer.write { db in
            try LocalActivityRow(activity, state: .recorded).insert(db)
            var operation = SyncOperationRecord(
                type: ActivityOperationStep.create.rawValue,
                entityId: activity.id.description,
                nextAttemptAt: now,
                createdAt: now
            )
            try operation.insert(db)
            try db.execute(sql: "DELETE FROM recording WHERE activity_id = ?", arguments: [activity.id.description])
        }
    }

    // MARK: - Reading

    func activity(_ id: ActivityID) async throws -> LocalActivity? {
        try await database.writer.read { db in
            try LocalActivityRow.fetchOne(db, key: id.description)?.activity
        }
    }

    /// Every local Activity, newest first.
    func activities() async throws -> [LocalActivity] {
        try await database.writer.read { db in
            try LocalActivityRow.order(Column("started_at_ms").desc).fetchAll(db).compactMap(\.activity)
        }
    }

    func activityIDs(in state: LocalActivityState) async throws -> [ActivityID] {
        try await database.writer.read { db in
            try LocalActivityRow.filter(Column("state") == state.rawValue).fetchAll(db).compactMap(\.activity?.id)
        }
    }

    /// Oldest first; at most one per Activity.
    func pendingOperations() async throws -> [PendingActivityOperation] {
        try await database.writer.read { db in
            try Self.operations.order(SyncOperationRecord.Columns.id).fetchAll(db).compactMap(PendingActivityOperation.init)
        }
    }

    func operation(for id: ActivityID) async throws -> PendingActivityOperation? {
        try await database.writer.read { db in
            try Self.operation(for: id, db)
        }
    }

    /// The raw points (time order) and finished Pauses of an Activity, for its trace.
    func trace(of id: ActivityID) async throws -> (points: [LocationSample], pauses: [TracePauseInterval]) {
        try await database.writer.read { db in
            let points = try Row.fetchAll(db, sql: """
                SELECT timestamp_ms, latitude, longitude, altitude_m, horizontal_accuracy_m, speed_ms
                FROM activity_point WHERE activity_id = ? ORDER BY timestamp_ms, id
                """, arguments: [id.description]).map { row in
                LocationSample(
                    coordinate: Coordinate(latitude: row["latitude"], longitude: row["longitude"]),
                    altitude: row["altitude_m"],
                    horizontalAccuracy: row["horizontal_accuracy_m"],
                    speed: row["speed_ms"],
                    timestamp: Date(epochMilliseconds: row["timestamp_ms"])
                )
            }
            let pauses = try Row.fetchAll(db, sql: """
                SELECT start_ms, end_ms FROM activity_pause WHERE activity_id = ? ORDER BY start_ms
                """, arguments: [id.description]).map { TracePauseInterval(startMs: $0["start_ms"], endMs: $0["end_ms"]) }
            return (points, pauses)
        }
    }

    // MARK: - Transitions (ADR-031 §14)

    /// The step succeeded: the Activity goes to `state` and `next` replaces the operation, in
    /// one transaction. Returns the new operation, due now.
    @discardableResult
    func advance(
        _ operation: PendingActivityOperation,
        to state: LocalActivityState,
        next: ActivityOperationStep?,
        uploadTarget: TraceUploadTarget? = nil,
        at date: Date
    ) async throws -> PendingActivityOperation? {
        try await database.writer.write { db in
            guard try SyncOperationRecord.deleteOne(db, key: operation.id) else {
                // Deleted on the phone while the step was on its way (ADR-031 §14): a creation
                // that just succeeded leaves a server copy to delete.
                guard operation.step == .create,
                      try LocalActivityRow.fetchOne(db, key: operation.activityID.description) == nil,
                      try Self.operation(for: operation.activityID, db) == nil
                else { return nil }
                return try Self.queueDelete(of: operation.activityID, at: date, db)
            }
            try Self.setState(state, failure: nil, of: operation.activityID, db)
            guard let next else { return nil }
            var record = SyncOperationRecord(
                type: next.rawValue,
                entityId: operation.activityID.description,
                payload: try uploadTarget.map(Self.payload),
                nextAttemptAt: date,
                createdAt: date
            )
            try record.insert(db)
            return PendingActivityOperation(record)
        }
    }

    /// Temporary failure: tried again at `date`.
    func postpone(_ operation: PendingActivityOperation, until date: Date, error: String) async throws {
        try await database.writer.write { db in
            guard var record = try SyncOperationRecord.fetchOne(db, key: operation.id) else { return }
            record.attempts += 1
            record.nextAttemptAt = date
            record.lastError = error
            try record.update(db)
        }
    }

    /// Keeps (or forgets, with `nil`) the upload URL of an `upload_trace` operation.
    func setUploadTarget(_ target: TraceUploadTarget?, of operation: PendingActivityOperation) async throws {
        try await database.writer.write { db in
            guard var record = try SyncOperationRecord.fetchOne(db, key: operation.id) else { return }
            record.payload = try target.map(Self.payload)
            try record.update(db)
        }
    }

    /// Refused by the API: `failed` with the reason, the operation dropped. Retry (#67) goes back
    /// to the state the Activity was in.
    func fail(_ operation: PendingActivityOperation, reason: String) async throws {
        try await database.writer.write { db in
            _ = try SyncOperationRecord.deleteOne(db, key: operation.id)
            let current = try LocalActivityRow.fetchOne(db, key: operation.activityID.description)?.state
            let resume = current.flatMap(LocalActivityState.init(rawValue:)) ?? .recorded
            try Self.setState(.failed, failure: LocalActivityFailure(reason: reason, resumeState: resume), of: operation.activityID, db)
        }
    }

    /// Failed by the worker (`GET /v1/activities/:id`): the points are kept.
    func markFailed(_ id: ActivityID, reason: String) async throws {
        try await database.writer.write { db in
            try Self.setState(.failed, failure: LocalActivityFailure(reason: reason, resumeState: .processing), of: id, db)
        }
    }

    /// Processed by the server: the local Activity, its points, Pauses and operations go.
    func wipe(_ ids: [ActivityID]) async throws {
        try await database.writer.write { db in
            try Self.wipe(ids.map(\.description), db)
        }
    }

    // MARK: - Delete, Retry, sign-out (ADR-031 §14)

    /// Delete: unknown to the server, the Activity, its points, Pauses and queued steps go at
    /// once. If the server already has it (or may have it: a creation was attempted), its queued
    /// steps give way to `delete_activity` in the same transaction and the local copy stays,
    /// hidden from the feed, until the server answers; returns `true` then.
    @discardableResult
    func delete(_ id: ActivityID) async throws -> Bool {
        let now = now()
        return try await database.writer.write { db in
            guard let activity = try LocalActivityRow.fetchOne(db, key: id.description)?.activity else { return false }
            guard activity.canBeDeleted else { throw LocalActivityActionError.notAllowed }
            let pending = try Self.operation(for: id, db)
            if pending?.step == .delete { return true }
            let creationAttempted = pending.map { $0.step == .create && $0.attempts > 0 } ?? false
            guard activity.isKnownToServer || creationAttempted else {
                try Self.wipe([id.description], db)
                return false
            }
            _ = try Self.operations.filter(SyncOperationRecord.Columns.entityID == id.description).deleteAll(db)
            try Self.queueDelete(of: id, at: now, db)
            return true
        }
    }

    /// Retry after an API refusal: back to the state before the failure, the refused step
    /// queued again, due now.
    func retry(_ id: ActivityID) async throws {
        let now = now()
        try await database.writer.write { db in
            guard let activity = try LocalActivityRow.fetchOne(db, key: id.description)?.activity,
                  activity.canBeRetried, let resume = activity.failure?.resumeState
            else { throw LocalActivityActionError.notAllowed }
            let step: ActivityOperationStep
            switch resume {
            case .recorded: step = .create
            case .created: step = .upload
            case .traceUploaded: step = .complete
            case .processing, .failed: throw LocalActivityActionError.notAllowed
            }
            try Self.setState(resume, failure: nil, of: id, db)
            var record = SyncOperationRecord(type: step.rawValue, entityId: id.description, nextAttemptAt: now, createdAt: now)
            try record.insert(db)
        }
    }

    /// The server deleted it (`204`) or no longer has it (`404`): the local copy goes.
    func deleted(_ operation: PendingActivityOperation) async throws {
        try await database.writer.write { db in
            try Self.wipe([operation.activityID.description], db)
        }
    }

    /// `409`: the server already handed it to the worker. The Activity is shown again in
    /// `processing` and followed like any other.
    func deletionRefused(_ operation: PendingActivityOperation) async throws {
        try await database.writer.write { db in
            _ = try SyncOperationRecord.deleteOne(db, key: operation.id)
            try Self.setState(.processing, failure: nil, of: operation.activityID, db)
        }
    }

    /// The Activities a sign-out would lose: `recorded`, `created`, `trace_uploaded`, `failed`.
    /// One in `processing` is safe on the server; one being deleted is already given up.
    func unsentCount() async throws -> Int {
        try await database.writer.read { db in
            try LocalActivityRow
                .filter(Column("state") != LocalActivityState.processing.rawValue)
                .filter(!Self.beingDeleted.contains(Column("id")))
                .fetchCount(db)
        }
    }

    /// Sign-out: every local Activity, its points, Pauses and queued steps go.
    func clear() async throws {
        try await database.writer.write { db in
            let keys = try String.fetchAll(db, sql: "SELECT id FROM local_activity")
            try Self.wipe(keys, db)
            _ = try Self.operations.deleteAll(db)
        }
    }

    // MARK: - Internals

    static var operations: QueryInterfaceRequest<SyncOperationRecord> {
        SyncOperationRecord.filter(ActivityOperationStep.allCases.map(\.rawValue).contains(SyncOperationRecord.Columns.type))
    }

    /// Ids of the Activities waiting for the server to confirm their Delete.
    static var beingDeleted: QueryInterfaceRequest<SyncOperationRecord> {
        SyncOperationRecord
            .filter(SyncOperationRecord.Columns.type == ActivityOperationStep.delete.rawValue)
            .select(SyncOperationRecord.Columns.entityID)
    }

    static func operation(for id: ActivityID, _ db: Database) throws -> PendingActivityOperation? {
        try operations
            .filter(SyncOperationRecord.Columns.entityID == id.description)
            .order(SyncOperationRecord.Columns.id)
            .fetchOne(db)
            .flatMap(PendingActivityOperation.init)
    }

    private static func wipe(_ keys: [String], _ db: Database) throws {
        _ = try LocalActivityRow.filter(keys: keys).deleteAll(db)
        _ = try operations.filter(keys.contains(SyncOperationRecord.Columns.entityID)).deleteAll(db)
        for key in keys {
            try db.execute(sql: "DELETE FROM activity_point WHERE activity_id = ?", arguments: [key])
            try db.execute(sql: "DELETE FROM activity_pause WHERE activity_id = ?", arguments: [key])
        }
    }

    @discardableResult
    private static func queueDelete(of id: ActivityID, at date: Date, _ db: Database) throws -> PendingActivityOperation? {
        var record = SyncOperationRecord(
            type: ActivityOperationStep.delete.rawValue,
            entityId: id.description,
            nextAttemptAt: date,
            createdAt: date
        )
        try record.insert(db)
        return PendingActivityOperation(record)
    }

    private static func setState(_ state: LocalActivityState, failure: LocalActivityFailure?, of id: ActivityID, _ db: Database) throws {
        try db.execute(
            sql: "UPDATE local_activity SET state = ?, failure_reason = ?, failure_resume_state = ? WHERE id = ?",
            arguments: [state.rawValue, failure?.reason, failure?.resumeState.rawValue, id.description]
        )
    }

    private static func payload(_ target: TraceUploadTarget) throws -> String {
        String(decoding: try JSONEncoder().encode(target), as: UTF8.self)
    }
}

/// A finished Pause of an Activity, in trace v2 units (UTC epoch milliseconds).
struct TracePauseInterval: Equatable, Sendable {
    let startMs: Int64
    let endMs: Int64
}

// MARK: - Rows (shared with GRDBLocalActivityStore+Cards.swift)

struct LocalActivityRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_activity"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    var id: String
    var sportTypeCode: String
    var title: String
    var visibility: String
    var startedAtMs: Int64
    var endedAtMs: Int64
    var distanceM: Double
    var movingTimeS: Int
    var elapsedTimeS: Int
    var state: String
    var failureReason: String?
    var failureResumeState: String?

    init(_ activity: LocalActivity, state: LocalActivityState) {
        id = activity.id.description
        sportTypeCode = activity.sport.code
        title = activity.title
        visibility = activity.visibility.rawValue
        startedAtMs = activity.startedAt.epochMilliseconds
        endedAtMs = activity.endedAt.epochMilliseconds
        distanceM = activity.distance.meters
        movingTimeS = activity.movingTimeS
        elapsedTimeS = activity.elapsedTimeS
        self.state = state.rawValue
    }

    var activity: LocalActivity? {
        guard let uuid = UUID(uuidString: id),
              let visibility = ActivityVisibility(rawValue: visibility),
              let state = LocalActivityState(rawValue: state)
        else { return nil }
        let failure = failureReason.map { reason in
            LocalActivityFailure(
                reason: reason,
                resumeState: failureResumeState.flatMap(LocalActivityState.init(rawValue:)) ?? .recorded
            )
        }
        return LocalActivity(
            id: ActivityID(uuid),
            sport: SportType(code: sportTypeCode),
            title: title,
            visibility: visibility,
            startedAt: Date(epochMilliseconds: startedAtMs),
            endedAt: Date(epochMilliseconds: endedAtMs),
            distance: Distance(meters: distanceM),
            movingTimeS: movingTimeS,
            elapsedTimeS: elapsedTimeS,
            state: state,
            failure: failure
        )
    }
}

extension PendingActivityOperation {
    init?(_ record: SyncOperationRecord) {
        guard let id = record.id,
              let uuid = UUID(uuidString: record.entityId),
              let step = ActivityOperationStep(rawValue: record.type)
        else { return nil }
        let target = record.payload.flatMap { try? JSONDecoder().decode(TraceUploadTarget.self, from: Data($0.utf8)) }
        self.init(
            id: id,
            activityID: ActivityID(uuid),
            step: step,
            attempts: record.attempts,
            nextAttemptAt: record.nextAttemptAt,
            lastError: record.lastError,
            uploadTarget: target
        )
    }
}
