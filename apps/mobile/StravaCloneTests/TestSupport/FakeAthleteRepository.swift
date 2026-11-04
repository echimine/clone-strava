import Foundation
@testable import StravaClone

/// In-memory `AthleteRepository` (ADR-025 §3): scripted answers, recorded calls.
final class FakeAthleteRepository: AthleteRepository, @unchecked Sendable {
    private let lock = NSLock()

    var profileResult: Result<AthleteProfile, AthleteError> = .failure(.network)
    /// Answers keyed by cursor (`nil` = first page).
    var pages: [String?: Result<FeedPage, AthleteError>] = [:]

    private(set) var profileCalls: [String] = []
    private(set) var activityCalls: [(athleteId: String, cursor: String?)] = []

    func profile(of athleteId: String) async throws(AthleteError) -> AthleteProfile {
        let result = lock.withLock {
            profileCalls.append(athleteId)
            return profileResult
        }
        return try result.get()
    }

    func activities(of athleteId: String, cursor: String?) async throws(AthleteError) -> FeedPage {
        let result = lock.withLock {
            activityCalls.append((athleteId, cursor))
            return pages[cursor] ?? .failure(.network)
        }
        return try result.get()
    }
}

/// In-memory `ProfileRepository`: scripted answers, recorded calls, and a gate to observe the
/// optimistic state of "Approuver mes abonnés".
final class FakeProfileRepository: ProfileRepository, @unchecked Sendable {
    private let lock = NSLock()

    var editableResult: Result<EditableProfile, AthleteError> = .success(EditableProfile())
    var updateResult: Result<ActivityAuthor, AthleteError>?
    var approveResult: Result<Bool, AthleteError>?
    /// Suspends `setApproveFollowers` until resumed.
    var approveGate: AsyncStream<Void>?

    private(set) var updates: [ProfileUpdate] = []
    private(set) var approveCalls: [Bool] = []

    func editableProfile() async throws(AthleteError) -> EditableProfile {
        try lock.withLock { editableResult }.get()
    }

    func update(_ update: ProfileUpdate) async throws(AthleteError) -> ActivityAuthor {
        let result = lock.withLock {
            updates.append(update)
            return updateResult
        } ?? .success(ActivityAuthor(id: "me", displayName: update.name.displayName, avatarURL: nil))
        return try result.get()
    }

    func setApproveFollowers(_ approve: Bool) async throws(AthleteError) -> Bool {
        lock.withLock { approveCalls.append(approve) }
        if let gate = approveGate {
            for await _ in gate { break }
        }
        return try (lock.withLock { approveResult } ?? .success(approve)).get()
    }
}

extension AthleteProfile {
    static func fixture(
        id: String = "me",
        displayName: String = "Camille Martin",
        avatarURL: URL? = nil,
        activityCount: Int = 42,
        streakWeeks: Int = 5,
        followerCount: Int = 12,
        followingCount: Int = 8,
        viewerFollowStatus: FollowStatus? = nil,
        approveFollowers: Bool? = false,
        pendingFollowRequestCount: Int? = 0,
        itineraryCount: Int? = 3
    ) -> AthleteProfile {
        AthleteProfile(
            athlete: ActivityAuthor(id: id, displayName: displayName, avatarURL: avatarURL),
            activityCount: activityCount,
            streakWeeks: streakWeeks,
            followerCount: followerCount,
            followingCount: followingCount,
            viewerFollowStatus: viewerFollowStatus,
            followersYouKnow: [],
            practicedSports: [.run],
            approveFollowers: approveFollowers,
            pendingFollowRequestCount: pendingFollowRequestCount,
            itineraryCount: itineraryCount
        )
    }
}
