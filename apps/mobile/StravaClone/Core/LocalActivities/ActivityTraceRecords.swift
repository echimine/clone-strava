import Foundation
import GRDB

/// The raw points and finished Pauses of an Activity, keyed by its UUID (tables
/// `activity_point` / `activity_pause`, migration `recording_v1`), owned by
/// `Core/LocalActivities` (ADR-031 §15). The Recording writes them through it while it runs,
/// inside its own transactions; they then stay attached to the local Activity until it is wiped.
/// Times are UTC epoch milliseconds, the trace v2 unit.
enum ActivityTraceRecords {
    static func appendPoint(_ sample: LocationSample, to id: ActivityID, _ db: Database) throws {
        try PointRow(sample, activityID: id).insert(db)
    }

    static func appendPause(_ pause: TracePauseInterval, to id: ActivityID, _ db: Database) throws {
        try PauseRow(pause, activityID: id).insert(db)
    }

    static func pauseCount(of id: ActivityID, _ db: Database) throws -> Int {
        try PauseRow.filter(Column("activity_id") == id.description).fetchCount(db)
    }

    /// Time order (insertion order for equal times).
    static func points(of id: ActivityID, _ db: Database) throws -> [LocationSample] {
        try PointRow
            .filter(Column("activity_id") == id.description)
            .order(Column("timestamp_ms"), Column("id"))
            .fetchAll(db)
            .map(\.sample)
    }

    /// The route only, time order: for the feed card.
    static func coordinates(of id: ActivityID, _ db: Database) throws -> [Coordinate] {
        try Row.fetchAll(db, sql: """
            SELECT latitude, longitude FROM activity_point WHERE activity_id = ? ORDER BY timestamp_ms, id
            """, arguments: [id.description]).map { Coordinate(latitude: $0["latitude"], longitude: $0["longitude"]) }
    }

    static func pauses(of id: ActivityID, _ db: Database) throws -> [TracePauseInterval] {
        try PauseRow
            .filter(Column("activity_id") == id.description)
            .order(Column("start_ms"))
            .fetchAll(db)
            .map(\.interval)
    }

    /// Points and Pauses of these Activities (UUID strings) go.
    static func delete(of keys: [String], _ db: Database) throws {
        _ = try PointRow.filter(keys.contains(Column("activity_id"))).deleteAll(db)
        _ = try PauseRow.filter(keys.contains(Column("activity_id"))).deleteAll(db)
    }
}

/// A finished Pause of an Activity, in trace v2 units (UTC epoch milliseconds).
struct TracePauseInterval: Equatable, Sendable {
    let startMs: Int64
    let endMs: Int64

    init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    init(start: Date, end: Date) {
        self.init(startMs: start.epochMilliseconds, endMs: end.epochMilliseconds)
    }

    var start: Date { Date(epochMilliseconds: startMs) }
    var end: Date { Date(epochMilliseconds: endMs) }
}

// MARK: - Rows

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

    init(_ pause: TracePauseInterval, activityID: ActivityID) {
        activityId = activityID.description
        startMs = pause.startMs
        endMs = pause.endMs
    }

    var interval: TracePauseInterval {
        TracePauseInterval(startMs: startMs, endMs: endMs)
    }
}
