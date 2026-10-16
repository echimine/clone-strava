import Foundation
@testable import StravaClone

/// In-memory `ActivityKudosRepository`: kudos pages scripted in order (the last one repeats),
/// a scripted give/remove answer, recorded calls.
final class FakeActivityKudosRepository: ActivityKudosRepository, @unchecked Sendable {
    struct PageRequest: Equatable {
        let activityId: ActivityID
        let cursor: String?
        let limit: Int
    }

    private let lock = NSLock()
    private var pages: [Result<KudosPage, ActivityDetailError>]
    private(set) var pageRequests: [PageRequest] = []
    private(set) var setRequests: [Bool] = []
    /// Answers a give (`true`) or remove (`false`); runs while the request is "in flight".
    /// Throws an `ActivityDetailError` to fail (typed-throws closures need iOS 18).
    var onSetKudos: @Sendable (Bool) async throws -> KudosState = { given in
        KudosState(kudosCount: given ? 1 : 0, viewerHasKudoed: given)
    }

    init(_ pages: Result<KudosPage, ActivityDetailError>...) {
        self.pages = pages
    }

    func kudos(activityId: ActivityID, cursor: String?, limit: Int) async throws(ActivityDetailError) -> KudosPage {
        let result = lock.withLock {
            pageRequests.append(PageRequest(activityId: activityId, cursor: cursor, limit: limit))
            return pages.count > 1 ? pages.removeFirst() : pages.first ?? .success(KudosPage(givers: [], nextCursor: nil))
        }
        return try result.get()
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(ActivityDetailError) -> KudosState {
        let handler = lock.withLock {
            setRequests.append(given)
            return onSetKudos
        }
        do {
            return try await handler(given)
        } catch let error as ActivityDetailError {
            throw error
        } catch {
            throw .network
        }
    }
}

extension KudosGiver {
    static func fixture(_ index: Int) -> KudosGiver {
        KudosGiver(
            athlete: ActivityAuthor(id: "athlete-\(index)", displayName: "Athlète \(index)", avatarURL: nil),
            givenAt: Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 60)
        )
    }

    static func fixtures(_ range: Range<Int>) -> [KudosGiver] {
        range.map(fixture)
    }
}
