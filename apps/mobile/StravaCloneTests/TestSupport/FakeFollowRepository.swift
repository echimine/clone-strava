import Foundation
@testable import StravaClone

/// In-memory `FollowRepository` (ADR-025 §3): scripted answers, recorded calls, and a gate to
/// observe the optimistic state while a request is in flight.
final class FakeFollowRepository: FollowRepository, @unchecked Sendable {
    enum Call: Equatable {
        case follow(String)
        case unfollow(String)
    }

    private let lock = NSLock()

    /// The answer to a follow; by default accepted, with 1 more follower than `followerCount`.
    var followResult: Result<FollowStatus, AthleteError> = .success(.accepted)
    var unfollowResult: Result<FollowStatus, AthleteError> = .success(.none)
    var followerCount = 10
    /// Suspends every call until resumed.
    var gate: AsyncStream<Void>?

    private(set) var calls: [Call] = []

    func follow(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await answer(.follow(athleteId), athleteId) { $0.followResult }
    }

    func unfollow(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await answer(.unfollow(athleteId), athleteId) { $0.unfollowResult }
    }

    private func answer(
        _ call: Call,
        _ athleteId: String,
        _ result: (FakeFollowRepository) -> Result<FollowStatus, AthleteError>
    ) async throws(AthleteError) -> FollowChange {
        lock.withLock { calls.append(call) }
        if let gate {
            for await _ in gate { break }
        }
        let (status, count) = lock.withLock { (result(self), followerCount) }
        let followed = try status.get()
        return FollowChange(athleteId: athleteId, status: followed, followerCount: followed == .accepted ? count + 1 : count)
    }
}
