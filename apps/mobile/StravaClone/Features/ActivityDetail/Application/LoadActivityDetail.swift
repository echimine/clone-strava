import Foundation

/// Loads one Activity for its detail screen (ADR-033 §3).
struct LoadActivityDetail: Sendable {
    let repository: any ActivityDetailRepository

    func callAsFunction(_ id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail {
        try await repository.detail(id: id)
    }
}
