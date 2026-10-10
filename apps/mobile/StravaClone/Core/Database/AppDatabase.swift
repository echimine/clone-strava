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
            // Placeholder: activities, GPS points and sync_operation tables come with ADR-008.
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
        return migrator
    }
}
