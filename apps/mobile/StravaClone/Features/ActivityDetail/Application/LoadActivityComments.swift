import Foundation

/// A page of an Activity's comments (ADR-034 §3): the newest, or the one before `before`.
struct LoadActivityComments: Sendable {
    let repository: any ActivityCommentRepository

    func callAsFunction(_ activityId: ActivityID, before: String? = nil) async throws(ActivityCommentError) -> ActivityCommentsPage {
        try await repository.comments(activityId: activityId, before: before)
    }
}
