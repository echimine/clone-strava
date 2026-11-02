import Foundation
import GRDB

/// GRDB adapter of `OnboardingSubmissionQueue`: the one `submit_onboarding_answers` row of
/// `sync_operation` (ADR-008 §3, ADR-035 §5), without payload.
struct GRDBOnboardingSubmissionQueue: OnboardingSubmissionQueue {
    static let type = "submit_onboarding_answers"
    /// `entity_id` is required: the account's only Onboarding answers.
    private static let entityID = "onboarding_answers"

    let database: AppDatabase

    private static var rows: QueryInterfaceRequest<SyncOperationRecord> {
        SyncOperationRecord.filter(SyncOperationRecord.Columns.type == type)
    }

    func pending() async throws -> PendingOnboardingSubmission? {
        try await database.writer.read { db in
            try Self.rows.fetchOne(db).map { PendingOnboardingSubmission(attempts: $0.attempts, nextAttemptAt: $0.nextAttemptAt) }
        }
    }

    func enqueue(at date: Date) async throws {
        try await database.writer.write { db in
            guard try Self.rows.fetchCount(db) == 0 else { return }
            var record = SyncOperationRecord(type: Self.type, entityId: Self.entityID, nextAttemptAt: date, createdAt: date)
            try record.insert(db)
        }
    }

    func postpone(until date: Date, error: String) async throws {
        try await database.writer.write { db in
            guard var record = try Self.rows.fetchOne(db) else { return }
            record.attempts += 1
            record.nextAttemptAt = date
            record.lastError = error
            try record.update(db)
        }
    }

    func remove() async throws {
        _ = try await database.writer.write { db in
            try Self.rows.deleteAll(db)
        }
    }
}
