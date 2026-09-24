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
        return migrator
    }
}
