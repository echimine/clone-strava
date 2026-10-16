import Foundation

/// Deletes a comment, by its author or the Activity's (ADR-034 §3).
struct DeleteActivityComment: Sendable {
    let repository: any ActivityCommentRepository

    func callAsFunction(_ id: UUID, on activityId: ActivityID) async throws(ActivityCommentError) {
        try await repository.delete(activityId: activityId, id: id)
    }
}
