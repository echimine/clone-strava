import Foundation
@testable import StravaClone

/// In-memory `AthleteSearchRepository` (ADR-025 §3): answers by query, recorded calls, and a
/// gate to hold a request in flight.
final class FakeAthleteSearchRepository: AthleteSearchRepository, @unchecked Sendable {
    private let lock = NSLock()

    var results: [String: Result<[AthleteListItem], AthleteError>] = [:]
    /// Suspends every call until resumed.
    var gate: AsyncStream<Void>?

    private(set) var queries: [String] = []
    /// The queries whose task was cancelled while they were in flight.
    private(set) var cancelled: [String] = []

    func search(_ query: String) async throws(AthleteError) -> [AthleteListItem] {
        lock.withLock { queries.append(query) }
        if let gate {
            for await _ in gate { break }
        }
        if Task.isCancelled {
            lock.withLock { cancelled.append(query) }
            // URLSession throws on cancellation, which the adapter maps to a network error.
            throw .network
        }
        return try (lock.withLock { results[query] } ?? .success([])).get()
    }
}

extension AthleteListItem {
    static func fixture(_ id: String, _ name: String, status: FollowStatus? = FollowStatus.none) -> AthleteListItem {
        AthleteListItem(athlete: ActivityAuthor(id: id, displayName: name, avatarURL: nil), viewerFollowStatus: status)
    }
}
