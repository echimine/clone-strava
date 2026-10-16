import Foundation

/// One comment, after a realtime `comment.created` / `comment.updated` (ADR-034 §3, §5).
struct LoadActivityComment: Sendable {
    let repository: any ActivityCommentRepository

    func callAsFunction(_ id: UUID, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.comment(activityId: activityId, id: id)
    }
}
