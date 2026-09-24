import Foundation
import GRDB

/// GRDB adapter of `RecordingRepository`. Tables arrive with the Recording migrations (ADR-008).
struct GRDBRecordingRepository: RecordingRepository {
    let database: AppDatabase

    func create(_ recording: ActiveRecording) async throws {
        try await database.writer.write { _ in
            // TODO(ADR-008): insert the activity with state `recording`.
        }
    }

    func append(_ sample: LocationSample, to id: ActivityID) async throws {
        try await database.writer.write { _ in
            // TODO(ADR-008): insert the GPS point immediately.
        }
    }

    func finish(_ id: ActivityID, at date: Date) async throws {
        try await database.writer.write { _ in
            // TODO(ADR-008): move to `recorded` and enqueue `create_activity` in sync_operation.
        }
    }
}
