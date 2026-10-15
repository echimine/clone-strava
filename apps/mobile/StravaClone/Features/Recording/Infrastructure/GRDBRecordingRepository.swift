import Foundation
import GRDB

/// GRDB adapter of `RecordingRepository` (ADR-031 §10, migration `recording_v1`): the
/// `recording` row; the points and finished Pauses of its Activity UUID are written through
/// `Core/LocalActivities` (`ActivityTraceRecords`, ADR-031 §15). WAL on disk
/// (`AppDatabase.onDisk`): one short transaction per point, ~1 Hz.
struct GRDBRecordingRepository: RecordingRepository {
    let database: AppDatabase

    func load() async throws -> StoredRecording? {
        try await database.writer.read { db in
            guard let row = try RecordingRow.fetchOne(db) else { return nil }
            guard let id = row.activityID else { return nil }
            let pauses = try ActivityTraceRecords.pauses(of: id, db).map { RecordingPause(start: $0.start, end: $0.end) }
            guard let recording = row.recording(pauses: pauses) else { return nil }
            let points = try ActivityTraceRecords.points(of: id, db)
            return StoredRecording(recording: recording, points: points, itinerary: try Self.fetchItinerary(db))
        }
    }

    func create(_ recording: Recording) async throws {
        try await database.writer.write { db in
            guard try RecordingRow.fetchCount(db) == 0 else {
                throw RecordingRepositoryError.alreadyExists
            }
            try RecordingRow(recording).insert(db)
            try insertNewPauses(of: recording, db)
        }
    }

    func save(_ recording: Recording) async throws {
        try await database.writer.write { db in
            guard let row = try RecordingRow.fetchOne(db), row.activityId == recording.id.description else { return }
            try RecordingRow(recording).update(db)
            try insertNewPauses(of: recording, db)
        }
    }

    func append(_ point: LocationSample, to id: ActivityID) async throws -> Bool {
        try await database.writer.write { db in
            guard let row = try RecordingRow.fetchOne(db),
                  row.activityId == id.description,
                  row.phase == RecordingPhase.active.rawValue
            else { return false }
            try ActivityTraceRecords.appendPoint(point, to: id, db)
            return true
        }
    }

    func delete(_ id: ActivityID) async throws {
        try await database.writer.write { db in
            try Self.close(id, db)
            try ActivityTraceRecords.delete(of: [id.description], db)
        }
    }

    /// The `recording` row goes (Save: inside the Save transaction of `Core/LocalActivities`;
    /// the points and Pauses stay with the local Activity).
    static func close(_ id: ActivityID, _ db: Database) throws {
        try RecordingRow.filter(Column("activity_id") == id.description).deleteAll(db)
    }

    /// Pauses are only ever appended: the stored ones are the first ones of the Recording.
    private func insertNewPauses(of recording: Recording, _ db: Database) throws {
        let stored = try ActivityTraceRecords.pauseCount(of: recording.id, db)
        for pause in recording.pauses.dropFirst(stored) {
            try ActivityTraceRecords.appendPause(TracePauseInterval(start: pause.start, end: pause.end), to: recording.id, db)
        }
    }
}

// MARK: - Rows

private struct RecordingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recording"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    var id = 1
    var activityId: String
    var sportTypeCode: String
    var startedAtMs: Int64
    var phase: String
    var pauseStartedAtMs: Int64?
    var pauseKind: String?
    var pauseLatitude: Double?
    var pauseLongitude: Double?
    var autoPauseEnabled: Bool

    init(_ recording: Recording) {
        activityId = recording.id.description
        sportTypeCode = recording.sport.rawValue
        startedAtMs = recording.startedAt.epochMilliseconds
        phase = recording.phase.rawValue
        pauseStartedAtMs = recording.currentPauseStartedAt?.epochMilliseconds
        pauseKind = recording.currentPauseKind?.rawValue
        pauseLatitude = recording.currentPausePosition?.latitude
        pauseLongitude = recording.currentPausePosition?.longitude
        autoPauseEnabled = recording.autoPauseEnabled
    }

    var activityID: ActivityID? {
        UUID(uuidString: activityId).map(ActivityID.init)
    }

    func recording(pauses: [RecordingPause]) -> Recording? {
        guard let uuid = UUID(uuidString: activityId),
              let sport = RecordingSport(rawValue: sportTypeCode),
              let phase = RecordingPhase(rawValue: phase)
        else { return nil }
        return Recording(
            id: ActivityID(uuid),
            sport: sport,
            startedAt: Date(epochMilliseconds: startedAtMs),
            phase: phase,
            currentPauseStartedAt: pauseStartedAtMs.map(Date.init(epochMilliseconds:)),
            pauses: pauses,
            currentPauseKind: pauseKind.flatMap(RecordingPauseKind.init(rawValue:)),
            currentPausePosition: pausePosition,
            autoPauseEnabled: autoPauseEnabled
        )
    }

    private var pausePosition: Coordinate? {
        guard let pauseLatitude, let pauseLongitude else { return nil }
        return Coordinate(latitude: pauseLatitude, longitude: pauseLongitude)
    }
}
