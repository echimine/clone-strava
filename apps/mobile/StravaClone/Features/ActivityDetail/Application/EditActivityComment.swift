import Foundation

/// The author's edit of their comment (ADR-034 §3).
struct EditActivityComment: Sendable {
    let repository: any ActivityCommentRepository

    func callAsFunction(_ id: UUID, body: String, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.edit(activityId: activityId, id: id, body: body)
    }
}
