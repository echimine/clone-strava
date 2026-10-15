import Foundation
import GRDB

/// Local SQLite database, source of truth for the UI (ADR-008).
/// Each feature declares its own migrations here, prefixed with its name.
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// WAL database in Application Support: concurrent reads while GPS points are written (ADR-006).
    static func onDisk(fileName: String = "db.sqlite") throws -> AppDatabase {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let pool = try DatabasePool(path: directory.appendingPathComponent(fileName).path)
        return try AppDatabase(pool)
    }

    /// In-memory database for tests and previews, with the real migrations.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1") { _ in
            // Placeholder: activities and GPS points tables come with ADR-008.
        }
        // ADR-030 §8: the athlete's Itineraries, without Waypoints or Legs. Dates are seconds since 2001
        // (REAL, `Date`'s own storage), so the API's milliseconds survive the round trip.
        migrator.registerMigration("itineraries_v1") { db in
            try db.create(table: "itinerary") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("sport_type_code", .text).notNull()
                table.column("distance_m", .double).notNull()
                table.column("elevation_gain_m", .double).notNull()
                table.column("map_polyline", .text).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "itinerary_on_updated_at", on: "itinerary", columns: ["updated_at", "id"])
            // `updated_at` of the detail: an older one than its row's is fetched again (#35).
            try db.create(table: "itinerary_detail") { table in
                table.primaryKey("itinerary_id", .text).references("itinerary", onDelete: .cascade)
                table.column("elevation_source", .text).notNull()
                table.column("track_polyline6", .text).notNull()
                table.column("track_altitudes_m", .jsonText).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
        }
        // ADR-008 §3: the sync queue, one row per operation to send. `type` names the operation
        // (`rename_itinerary`, `delete_itinerary`…), `entity_id` its target, `payload` its JSON
        // arguments. Dates are seconds since 2001, like the Itinerary tables.
        migrator.registerMigration("sync_operation_v1") { db in
            try db.create(table: "sync_operation") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("payload", .jsonText)
                table.column("attempts", .integer).notNull().defaults(to: 0)
                table.column("next_attempt_at", .double).notNull()
                table.column("last_error", .text)
                table.column("created_at", .double).notNull()
            }
            try db.create(index: "sync_operation_on_entity_id", on: "sync_operation", columns: ["entity_id", "type"])
        }
        // ADR-031 §10: the Recording in progress (one row at most, `id` = 1), and the raw points and
        // finished Pauses of an Activity keyed by its UUID. Points and Pauses outlive the Recording
        // row: on Save they stay attached to the local Activity (ADR-031 §11, Core/LocalActivities).
        // Times are UTC epoch milliseconds, the trace v2 unit, so a point sitting exactly on a Pause
        // boundary stays exactly on it (ADR-031 §12).
        migrator.registerMigration("recording_v1") { db in
            try db.create(table: "recording") { table in
                table.primaryKey("id", .integer).check { $0 == 1 }
                table.column("activity_id", .text).notNull()
                table.column("sport_type_code", .text).notNull()
                table.column("started_at_ms", .integer).notNull()
                table.column("phase", .text).notNull()
                table.column("pause_started_at_ms", .integer)
            }
            try db.create(table: "activity_point") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("activity_id", .text).notNull()
                table.column("timestamp_ms", .integer).notNull()
                table.column("latitude", .double).notNull()
                table.column("longitude", .double).notNull()
                table.column("altitude_m", .double)
                table.column("horizontal_accuracy_m", .double).notNull()
                table.column("speed_ms", .double)
            }
            try db.create(index: "activity_point_on_activity_id", on: "activity_point", columns: ["activity_id", "timestamp_ms"])
            try db.create(table: "activity_pause") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("activity_id", .text).notNull()
                table.column("start_ms", .integer).notNull()
                table.column("end_ms", .integer).notNull()
            }
            try db.create(index: "activity_pause_on_activity_id", on: "activity_pause", columns: ["activity_id", "start_ms"])
        }
        // ADR-031 §14, §15 (Core/LocalActivities): a saved Activity until the server has processed
        // it, with its provisional values (no elevation gain). Its points and Pauses are the
        // `activity_point` / `activity_pause` rows of the same UUID; its operations
        // (`create_activity`, `upload_trace`, `complete_activity`) are rows of `sync_operation`.
        migrator.registerMigration("local_activities_v1") { db in
            try db.create(table: "local_activity") { table in
                table.primaryKey("id", .text)
                table.column("sport_type_code", .text).notNull()
                table.column("title", .text).notNull()
                table.column("visibility", .text).notNull()
                table.column("started_at_ms", .integer).notNull()
                table.column("ended_at_ms", .integer).notNull()
                table.column("distance_m", .double).notNull()
                table.column("moving_time_s", .integer).notNull()
                table.column("elapsed_time_s", .integer).notNull()
                table.column("state", .text).notNull()
                table.column("failure_reason", .text)
                table.column("failure_resume_state", .text)
            }
        }
        return migrator
    }
}
