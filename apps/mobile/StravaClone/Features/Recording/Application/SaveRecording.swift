import Foundation

enum RecordingSaveError: Error, Equatable {
    /// Below the sport's minimum duration, fewer than 2 points, or not on the finish screen.
    case notSavable
}

/// Save on the finish screen (ADR-031 §11): the finished Recording becomes a local Activity in
/// `recorded`, `create_activity` is queued, the picked Media get their `media_upload` rows
/// (ADR-037 §6) and the `recording` row goes, in one transaction (`LocalActivitySaving`,
/// Core/LocalActivities); then the Recording is released.
struct SaveRecording: Sendable {
    let service: RecordingService
    let activities: any LocalActivitySaving
    var timeZone: TimeZone = .current

    /// - Parameters:
    ///   - mediaFirst: the first Media goes before the map ("Mettre en premier").
    ///   - media: the rows of the picked Media, each at its `position`.
    func callAsFunction(
        title: String,
        visibility: ActivityVisibility,
        mediaFirst: Bool = false,
        media: [MediaUpload] = []
    ) async throws {
        let activities = activities
        let timeZone = timeZone
        try await service.save { snapshot in
            guard var activity = snapshot.localActivity(title: title, visibility: visibility, timeZone: timeZone) else {
                throw RecordingSaveError.notSavable
            }
            activity.mediaFirst = mediaFirst
            try await activities.saveRecorded(activity, media: media)
        }
    }
}
