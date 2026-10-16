import Foundation

/// Failures of the Activity detail, as the presentation needs them.
enum ActivityDetailError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// Unknown, deleted or no longer visible (`404 activity_not_found`).
    case notFound
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    case network
}

/// Activity detail port (ADR-007): implemented over the API in Infrastructure, faked in tests.
protocol ActivityDetailRepository: Sendable {
    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail
}
