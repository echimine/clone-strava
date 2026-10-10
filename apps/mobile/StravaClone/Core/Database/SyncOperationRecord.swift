import Foundation
import GRDB

/// One row of `sync_operation` (ADR-008 §3, migration `sync_operation_v1`): each feature
/// reads and writes the rows of its own operation types.
struct SyncOperationRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "sync_operation"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseDateDecodingStrategy: DatabaseDateDecodingStrategy { .timeIntervalSinceReferenceDate }
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { .timeIntervalSinceReferenceDate }

    enum Columns {
        static let id = Column("id")
        static let type = Column("type")
        static let entityID = Column("entity_id")
    }

    var id: Int64?
    var type: String
    var entityId: String
    /// JSON arguments of the operation, if it has any.
    var payload: String?
    var attempts: Int = 0
    var nextAttemptAt: Date
    var lastError: String?
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
