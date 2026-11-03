import Foundation
@testable import StravaClone

/// In-memory `FollowListRepository` (ADR-025 §3): scripted pages and answers, recorded calls.
final class FakeFollowListRepository: FollowListRepository, @unchecked Sendable {
    enum Call: Equatable {
        case list(AthleteFollowsRequest.List, String, cursor: String?)
        case requests(cursor: String?)
        case accept(String)
        case refuse(String)
        case remove(String)
    }

    private let lock = NSLock()

    /// Pages keyed by list and cursor (`nil` = first page); a missing page is empty.
    var pages: [AthleteFollowsRequest.List: [String?: Result<AthleteListPage, AthleteError>]] = [:]
    var requestPages: [String?: Result<FollowRequestPage, AthleteError>] = [:]
    var acceptResult: Result<Void, AthleteError> = .success(())
    var refuseResult: Result<Void, AthleteError> = .success(())
    var removeResult: Result<Void, AthleteError> = .success(())

    private(set) var calls: [Call] = []

    func list(_ list: AthleteFollowsRequest.List, of athleteId: String, cursor: String?) async throws(AthleteError) -> AthleteListPage {
        try lock.withLock {
            calls.append(.list(list, athleteId, cursor: cursor))
            return pages[list]?[cursor] ?? .success(AthleteListPage(items: [], nextCursor: nil))
        }.get()
    }

    func followRequests(cursor: String?) async throws(AthleteError) -> FollowRequestPage {
        try lock.withLock {
            calls.append(.requests(cursor: cursor))
            return requestPages[cursor] ?? .success(FollowRequestPage(items: [], nextCursor: nil))
        }.get()
    }

    func acceptRequest(from followerId: String) async throws(AthleteError) {
        try lock.withLock {
            calls.append(.accept(followerId))
            return acceptResult
        }.get()
    }

    func refuseRequest(from followerId: String) async throws(AthleteError) {
        try lock.withLock {
            calls.append(.refuse(followerId))
            return refuseResult
        }.get()
    }

    func removeFollower(_ followerId: String) async throws(AthleteError) {
        try lock.withLock {
            calls.append(.remove(followerId))
            return removeResult
        }.get()
    }
}

extension FollowRequest {
    static func fixture(_ id: String, _ name: String, status: FollowStatus = .none) -> FollowRequest {
        FollowRequest(
            athlete: ActivityAuthor(id: id, displayName: name, avatarURL: nil),
            viewerFollowStatus: status,
            requestedAt: Date(timeIntervalSince1970: 1_793_608_200)
        )
    }
}
