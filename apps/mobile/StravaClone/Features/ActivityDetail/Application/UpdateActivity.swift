import Foundation

/// Sends the author's edit of an Activity (ADR-033 §4, §7).
struct UpdateActivity: Sendable {
    let repository: any ActivityDetailRepository

    func callAsFunction(_ id: ActivityID, with edit: ActivityEdit) async throws(ActivityDetailError) -> ActivityDetail {
        try await repository.update(id: id, with: edit)
    }
}
