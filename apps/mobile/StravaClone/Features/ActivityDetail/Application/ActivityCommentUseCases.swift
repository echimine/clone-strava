import Foundation

/// The comment actions of the detail (ADR-034 §3, §6): trivial use cases over the port, kept
/// together because the comments store uses all of them.
struct ActivityCommentUseCases: Sendable {
    let repository: any ActivityCommentRepository

    func page(_ activityId: ActivityID, before: String? = nil) async throws(ActivityCommentError) -> ActivityCommentsPage {
        try await repository.comments(activityId: activityId, before: before)
    }

    func comment(_ id: UUID, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.comment(activityId: activityId, id: id)
    }

    func add(_ id: UUID, body: String, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.add(activityId: activityId, id: id, body: body)
    }

    func edit(_ id: UUID, body: String, on activityId: ActivityID) async throws(ActivityCommentError) -> ActivityComment {
        try await repository.edit(activityId: activityId, id: id, body: body)
    }

    func delete(_ id: UUID, on activityId: ActivityID) async throws(ActivityCommentError) {
        try await repository.delete(activityId: activityId, id: id)
    }
}
