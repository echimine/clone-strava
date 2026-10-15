import Foundation

enum RecordingSaveError: Error, Equatable {
    /// Below the sport's minimum duration, fewer than 2 points, or not on the finish screen.
    case notSavable
}

/// Save on the finish screen (ADR-031 §11): the finished Recording becomes a local Activity in
/// `recorded`, `create_activity` is queued and the `recording` row goes, in one transaction
/// (`LocalActivitySaving`, Core/LocalActivities); then the Recording is released.
struct SaveRecording: Sendable {
    let service: RecordingService
    let activities: any LocalActivitySaving
    var timeZone: TimeZone = .current

    func callAsFunction(title: String, visibility: ActivityVisibility) async throws {
        let activities = activities
        let timeZone = timeZone
        try await service.save { snapshot in
            guard let activity = snapshot.localActivity(title: title, visibility: visibility, timeZone: timeZone) else {
                throw RecordingSaveError.notSavable
            }
            try await activities.saveRecorded(activity)
        }
    }
}
