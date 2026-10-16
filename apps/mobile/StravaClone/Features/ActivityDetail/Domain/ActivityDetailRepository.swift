import Foundation

/// Failures of the Activity detail, as the presentation needs them.
enum ActivityDetailError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// Unknown, deleted or no longer visible (`404 activity_not_found`).
    case notFound
    /// An edit the server turned down (`422`), e.g. `activity_too_short_for_sport`.
    case invalid(code: String?)
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    case network
}

/// Activity detail port (ADR-007): implemented over the API in Infrastructure, faked in tests.
protocol ActivityDetailRepository: Sendable {
    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail
    /// The author's edit (ADR-033 §4); returns the detail as the server stored it.
    func update(id: ActivityID, with edit: ActivityEdit) async throws(ActivityDetailError) -> ActivityDetail
}
