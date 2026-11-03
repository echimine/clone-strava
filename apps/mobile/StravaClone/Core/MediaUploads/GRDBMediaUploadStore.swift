import Foundation
import GRDB

/// The `media_upload` rows (ADR-037 §5, migration `media_upload_v1`). Only the queue writes
/// them, the Activity's own tables never: a Media row outlives its local Activity (§6).
struct GRDBMediaUploadStore: Sendable {
    let database: AppDatabase

    // MARK: - Reading

    /// Every row, oldest first: the order of the selection.
    func all() async throws -> [MediaUpload] {
        try await database.writer.read { db in
            try MediaUploadRow.order(Column("created_at"), Column("position")).fetchAll(db).compactMap(\.upload)
        }
    }

    func upload(_ mediaID: UUID) async throws -> MediaUpload? {
        try await database.writer.read { db in
            try MediaUploadRow.fetchOne(db, key: Self.key(mediaID))?.upload
        }
    }

    /// Rows not yet confirmed, `failed` included: what the sign-out confirmation counts (#186).
    func count() async throws -> Int {
        try await database.writer.read { db in try MediaUploadRow.fetchCount(db) }
    }

    // MARK: - Writing

    /// New rows in `exporting`, in one transaction. `db` variant: in the caller's transaction
    /// (the Recording's Save, ADR-037 §6).
    func insert(_ uploads: [MediaUpload]) async throws {
        try await database.writer.write { db in try Self.insert(uploads, db) }
    }

    static func insert(_ uploads: [MediaUpload], _ db: Database) throws {
        for upload in uploads {
            try MediaUploadRow(upload).insert(db)
        }
    }

    /// Writes `upload` as it is, its `position` excepted; nothing if its row was deleted
    /// meanwhile ("Retirer"). Returns whether the row still existed. The position belongs to
    /// `reposition`: a copy read before a new order (an export, an API call) cannot undo it.
    @discardableResult
    func save(_ upload: MediaUpload) async throws -> Bool {
        try await database.writer.write { db in
            guard let stored = try MediaUploadRow.fetchOne(db, key: Self.key(upload.mediaID)) else { return false }
            var row = MediaUploadRow(upload)
            row.position = stored.position
            try row.update(db)
            return true
        }
    }

    /// A new Media order (#184): each row listed takes its index; the others are left alone.
    func reposition(_ positions: [UUID: Int]) async throws {
        try await database.writer.write { db in
            for (mediaID, position) in positions {
                try db.execute(
                    sql: "UPDATE media_upload SET position = ? WHERE media_id = ?",
                    arguments: [position, Self.key(mediaID)]
                )
            }
        }
    }

    func delete(_ mediaIDs: [UUID]) async throws {
        try await database.writer.write { db in
            _ = try MediaUploadRow.deleteAll(db, keys: mediaIDs.map(Self.key))
        }
    }

    func deleteAll() async throws {
        try await database.writer.write { db in _ = try MediaUploadRow.deleteAll(db) }
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}

/// One row of `media_upload`, as GRDB reads and writes it.
struct MediaUploadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_upload"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseDateDecodingStrategy: DatabaseDateDecodingStrategy { .timeIntervalSinceReferenceDate }
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { .timeIntervalSinceReferenceDate }

    var mediaId: String
    var activityId: String
    var kind: String
    var position: Int
    var state: String
    var failureReason: String?
    var width: Int?
    var height: Int?
    var durationMs: Int?
    var files: [MediaUploadFile]
    var attempts: Int
    var nextAttemptAt: Date
    var createdAt: Date

    init(_ upload: MediaUpload) {
        mediaId = upload.mediaID.uuidString.lowercased()
        activityId = upload.activityID.description
        kind = upload.kind.rawValue
        position = upload.position
        state = upload.state.rawValue
        failureReason = upload.failure?.rawValue
        width = upload.width
        height = upload.height
        durationMs = upload.durationMs
        files = upload.files
        attempts = upload.attempts
        nextAttemptAt = upload.nextAttemptAt
        createdAt = upload.createdAt
    }

    var upload: MediaUpload? {
        guard let mediaID = UUID(uuidString: mediaId), let activityUUID = UUID(uuidString: activityId),
              let kind = ActivityMedia.Kind(rawValue: kind), let state = MediaUploadState(rawValue: state)
        else { return nil }
        return MediaUpload(
            mediaID: mediaID,
            activityID: ActivityID(activityUUID),
            kind: kind,
            position: position,
            state: state,
            failure: failureReason.flatMap(MediaUploadFailure.init(rawValue:)),
            width: width,
            height: height,
            durationMs: durationMs,
            files: files,
            attempts: attempts,
            nextAttemptAt: nextAttemptAt,
            createdAt: createdAt
        )
    }
}
