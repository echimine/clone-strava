import Foundation

/// The author's delete of a processed Activity (ADR-033 §6, §7). Already gone (`404`, e.g.
/// deleted from another device) is what was asked: it does not fail.
struct DeleteActivity: Sendable {
    let repository: any ActivityDetailRepository

    func callAsFunction(_ id: ActivityID) async throws(ActivityDetailError) {
        do {
            try await repository.delete(id: id)
        } catch .notFound {
            return
        }
    }
}
