import Foundation

/// Sends a comment under its app-generated id (ADR-034 §2, §3): a replay returns the same one.
struct AddActivityComment: Sendable {
    let repository: any ActivityCommentRepository

    func callAsFunction(_ id: UUID, body: String, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.add(activityId: activityId, id: id, body: body)
    }
}
