import Foundation
import GRDB

/// GRDB adapter of `RecordingRepository` (ADR-031 §10, migration `recording_v1`): the
/// `recording` row, plus the `activity_point` and `activity_pause` rows of its Activity UUID.
/// WAL on disk (`AppDatabase.onDisk`): one short transaction per point, ~1 Hz.
struct GRDBRecordingRepository: RecordingRepository {
    let database: AppDatabase

    func load() async throws -> StoredRecording? {
        try await database.writer.read { db in
            guard let row = try RecordingRow.fetchOne(db) else { return nil }
            let activityID = row.activityId
            let pauses = try PauseRow
                .filter(Column("activity_id") == activityID)
                .order(Column("start_ms"))
                .fetchAll(db)
            let points = try PointRow
                .filter(Column("activity_id") == activityID)
                .order(Column("timestamp_ms"), Column("id"))
                .fetchAll(db)
            guard let recording = row.recording(pauses: pauses.map(\.pause)) else { return nil }
            return StoredRecording(recording: recording, points: points.map(\.sample), itinerary: try Self.fetchItinerary(db))
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
            try PointRow(point, activityID: id).insert(db)
            return true
        }
    }

    func delete(_ id: ActivityID) async throws {
        try await database.writer.write { db in
            try RecordingRow.filter(Column("activity_id") == id.description).deleteAll(db)
            try PointRow.filter(Column("activity_id") == id.description).deleteAll(db)
            try PauseRow.filter(Column("activity_id") == id.description).deleteAll(db)
        }
    }

    /// Pauses are only ever appended: the stored ones are the first ones of the Recording.
    private func insertNewPauses(of recording: Recording, _ db: Database) throws {
        let stored = try PauseRow.filter(Column("activity_id") == recording.id.description).fetchCount(db)
        for pause in recording.pauses.dropFirst(stored) {
            try PauseRow(pause, activityID: recording.id).insert(db)
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

    init(_ recording: Recording) {
        activityId = recording.id.description
        sportTypeCode = recording.sport.rawValue
        startedAtMs = recording.startedAt.epochMilliseconds
        phase = recording.phase.rawValue
        pauseStartedAtMs = recording.currentPauseStartedAt?.epochMilliseconds
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
            pauses: pauses
        )
    }
}

private struct PointRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_point"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    var id: Int64?
    var activityId: String
    var timestampMs: Int64
    var latitude: Double
    var longitude: Double
    var altitudeM: Double?
    var horizontalAccuracyM: Double
    var speedMs: Double?

    init(_ sample: LocationSample, activityID: ActivityID) {
        activityId = activityID.description
        timestampMs = sample.timestamp.epochMilliseconds
        latitude = sample.coordinate.latitude
        longitude = sample.coordinate.longitude
        altitudeM = sample.altitude
        horizontalAccuracyM = sample.horizontalAccuracy
        speedMs = sample.speed
    }

    var sample: LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            altitude: altitudeM,
            horizontalAccuracy: horizontalAccuracyM,
            speed: speedMs,
            timestamp: Date(epochMilliseconds: timestampMs)
        )
    }
}

private struct PauseRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_pause"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    var id: Int64?
    var activityId: String
    var startMs: Int64
    var endMs: Int64

    init(_ pause: RecordingPause, activityID: ActivityID) {
        activityId = activityID.description
        startMs = pause.start.epochMilliseconds
        endMs = pause.end.epochMilliseconds
    }

    var pause: RecordingPause {
        RecordingPause(start: Date(epochMilliseconds: startMs), end: Date(epochMilliseconds: endMs))
    }
}
