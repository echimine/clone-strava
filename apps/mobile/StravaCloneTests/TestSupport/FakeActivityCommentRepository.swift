import Foundation
@testable import StravaClone

/// In-memory `ActivityCommentRepository`: each route answers what its script says (the last
/// answer repeats; nil = echo the request as a stored comment), and every call is recorded.
final class FakeActivityCommentRepository: ActivityCommentRepository, @unchecked Sendable {
    enum Call: Equatable {
        case page(before: String?)
        case one(UUID)
        case add(UUID, String)
        case edit(UUID, String)
        case delete(UUID)
    }

    private let lock = NSLock()
    private var pages: [String?: Result<ActivityCommentsPage, ActivityCommentError>] = [:]
    private var addResults: [Result<ActivityComment, ActivityCommentError>?] = []
    private var editResults: [Result<ActivityComment, ActivityCommentError>?] = []
    private var deleteResults: [Result<Void, ActivityCommentError>] = []
    private var oneResults: [Result<ActivityComment, ActivityCommentError>] = []
    private(set) var calls: [Call] = []
    /// Holds the next `add`/`edit`/`delete` until `resume()`, to look at the optimistic state.
    private var gate: CheckedContinuation<Void, Never>?
    private var gated = false

    let author = ActivityAuthor(id: "me", displayName: "Camille Martin", avatarURL: nil)

    func setPage(before: String? = nil, _ result: Result<ActivityCommentsPage, ActivityCommentError>) {
        lock.withLock { pages[before] = result }
    }

    func scriptAdd(_ results: Result<ActivityComment, ActivityCommentError>?...) { lock.withLock { addResults = results } }
    func scriptEdit(_ results: Result<ActivityComment, ActivityCommentError>?...) { lock.withLock { editResults = results } }
    func scriptDelete(_ results: Result<Void, ActivityCommentError>...) { lock.withLock { deleteResults = results } }
    func scriptOne(_ results: Result<ActivityComment, ActivityCommentError>...) { lock.withLock { oneResults = results } }

    /// The next write waits for `resume()`.
    func holdNextWrite() { lock.withLock { gated = true } }

    func resume() {
        let gate = lock.withLock {
            defer { self.gate = nil }
            return self.gate
        }
        gate?.resume()
    }

    var isHoldingWrite: Bool { lock.withLock { gate != nil } }

    private func waitIfHeld() async {
        let held = lock.withLock {
            defer { gated = false }
            return gated
        }
        guard held else { return }
        await withCheckedContinuation { continuation in
            lock.withLock { gate = continuation }
        }
    }

    private static func next<T>(_ results: inout [T]) -> T? {
        results.count > 1 ? results.removeFirst() : results.first
    }

    func comments(activityId: ActivityID, before: String?) async throws(ActivityCommentError) -> ActivityCommentsPage {
        let result = lock.withLock {
            calls.append(.page(before: before))
            return pages[before] ?? .success(ActivityCommentsPage(items: [], previousCursor: nil))
        }
        return try result.get()
    }

    func comment(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) -> ActivityComment {
        let result = lock.withLock {
            calls.append(.one(id))
            return Self.next(&oneResults) ?? .failure(.notFound)
        }
        return try result.get()
    }

    func add(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        let script = lock.withLock {
            calls.append(.add(id, body))
            return Self.next(&addResults) ?? nil
        }
        await waitIfHeld()
        guard let script else { return .fixture(id: id, body: body, author: author, mine: true) }
        return try script.get()
    }

    func edit(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        let script = lock.withLock {
            calls.append(.edit(id, body))
            return Self.next(&editResults) ?? nil
        }
        await waitIfHeld()
        guard let script else {
            return .fixture(id: id, body: body, updatedAt: Date(timeIntervalSince1970: 1_790_100_000), author: author, mine: true)
        }
        return try script.get()
    }

    func delete(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) {
        let result = lock.withLock {
            calls.append(.delete(id))
            return Self.next(&deleteResults) ?? .success(())
        }
        await waitIfHeld()
        try result.get()
    }
}

extension ActivityComment {
    static func fixture(
        id: UUID = UUID(),
        body: String = "Belle sortie !",
        createdAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        updatedAt: Date? = nil,
        author: ActivityAuthor = ActivityAuthor(id: "u2", displayName: "Léa Durand", avatarURL: nil),
        mine: Bool = false,
        viewerCanDelete: Bool? = nil
    ) -> ActivityComment {
        ActivityComment(
            id: id,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            author: author,
            viewerCanEdit: mine,
            viewerCanDelete: viewerCanDelete ?? mine
        )
    }
}
