import Foundation
import GRDB

/// The Save transaction (ADR-031 §11) as the Recording needs it: `Core/LocalActivities` writes
/// the local Activity and its `create_activity`, and the `recording` row goes in the same
/// transaction. The points and finished Pauses stay attached to the Activity.
struct GRDBRecordingSaver: LocalActivitySaving {
    let activities: GRDBLocalActivityStore

    func saveRecorded(_ activity: LocalActivity) async throws {
        let id = activity.id
        try await activities.saveRecorded(activity) { db in
            try GRDBRecordingRepository.close(id, db)
        }
    }
}
