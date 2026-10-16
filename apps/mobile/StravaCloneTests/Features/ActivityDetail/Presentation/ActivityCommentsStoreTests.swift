import Foundation
import Testing
@testable import StravaClone

/// The comment thread of the detail (ADR-034 §6): chronological pages, optimistic send with
/// retry under the same id, optimistic edit and delete rolled back with a toast.
@MainActor
struct ActivityCommentsStoreTests {
    private let activityId = ActivityID()

    private func makeStore(
        _ repository: FakeActivityCommentRepository,
        onCountChange: @escaping @MainActor (Int) -> Void = { _ in }
    ) -> ActivityCommentsStore {
        ActivityCommentsStore(
            request: ActivityDetailRequest(id: activityId),
            useCases: ActivityCommentUseCases(repository: repository),
            viewer: { repository.author },
            onCountChange: onCountChange
        )
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + seconds) }

    @Test func loadsTheNewestCommentsThenTheOlderOnesAboveThem() async {
        let repository = FakeActivityCommentRepository()
        let older = ActivityComment.fixture(body: "Premier", createdAt: at(0))
        let middle = ActivityComment.fixture(body: "Deuxième", createdAt: at(60))
        let newest = ActivityComment.fixture(body: "Troisième", createdAt: at(120))
        repository.setPage(.success(ActivityCommentsPage(items: [middle, newest], previousCursor: "c1")))
        repository.setPage(before: "c1", .success(ActivityCommentsPage(items: [older], previousCursor: nil)))
        let store = makeStore(repository)

        await store.load()
        #expect(store.comments.map(\.comment) == [middle, newest])
        #expect(store.hasPreviousComments)

        await store.loadPrevious()
        #expect(store.comments.map(\.comment) == [older, middle, newest])
        #expect(store.comments.allSatisfy { $0.status == .sent })
        #expect(!store.hasPreviousComments)
        #expect(repository.calls == [.page(before: nil), .page(before: "c1")])
    }

    @Test func aFailedLoadOffersARetry() async {
        let repository = FakeActivityCommentRepository()
        repository.setPage(.failure(.offline))
        let store = makeStore(repository)

        await store.load()
        #expect(store.loadFailed)

        let comment = ActivityComment.fixture()
        repository.setPage(.success(ActivityCommentsPage(items: [comment], previousCursor: nil)))
        await store.load()
        #expect(!store.loadFailed)
        #expect(store.comments.map(\.comment) == [comment])
    }

    /// A reload (new appearance, realtime catch-up) refreshes the thread but keeps the comments
    /// not sent yet, still last.
    @Test func aReloadKeepsTheCommentsNotSentYet() async {
        let repository = FakeActivityCommentRepository()
        repository.scriptAdd(.failure(.offline))
        let store = makeStore(repository)
        store.draft = "Pas encore parti"
        await store.send()

        let other = ActivityComment.fixture(body: "Arrivé entre-temps")
        repository.setPage(.success(ActivityCommentsPage(items: [other], previousCursor: nil)))
        await store.load()

        #expect(store.comments.map(\.comment.body) == ["Arrivé entre-temps", "Pas encore parti"])
        #expect(store.comments.map(\.status) == [.sent, .failed])
    }

    @Test func aSentCommentAppearsAtOnceGreyedThenSent() async {
        let repository = FakeActivityCommentRepository()
        var countChanges: [Int] = []
        let store = makeStore(repository) { countChanges.append($0) }
        await store.load()
        repository.holdNextWrite()

        store.draft = "  Bravo !  "
        let send = Task { await store.send() }
        #expect(await eventually { repository.isHoldingWrite })

        let pending = store.comments.last
        #expect(store.comments.count == 1)
        #expect(pending?.status == .sending)
        #expect(pending?.comment.body == "Bravo !")
        #expect(pending?.comment.author == repository.author)
        #expect(store.draft.isEmpty)
        #expect(countChanges.isEmpty)

        repository.resume()
        await send.value
        #expect(store.comments.map(\.status) == [.sent])
        #expect(store.comments.first?.id == pending?.id)
        #expect(repository.calls.last == .add(pending!.id, "Bravo !"))
        #expect(countChanges == [1])
    }

    @Test func aBlankDraftSendsNothing() async {
        let repository = FakeActivityCommentRepository()
        let store = makeStore(repository)
        store.draft = "   \n "

        await store.send()

        #expect(store.comments.isEmpty)
        #expect(repository.calls.isEmpty)
    }

    @Test func aFailedSendKeepsItsTextAndRetriesUnderTheSameId() async {
        let repository = FakeActivityCommentRepository()
        repository.scriptAdd(.failure(.offline), nil)
        var countChanges: [Int] = []
        let store = makeStore(repository) { countChanges.append($0) }

        store.draft = "Superbe"
        await store.send()
        let failed = store.comments.first
        #expect(failed?.status == .failed)
        #expect(failed?.comment.body == "Superbe")
        #expect(countChanges.isEmpty)

        await store.retry(failed!.id)
        #expect(store.comments.map(\.status) == [.sent])
        #expect(repository.calls == [.add(failed!.id, "Superbe"), .add(failed!.id, "Superbe")])
        #expect(countChanges == [1])
    }

    // MARK: - Comments from elsewhere (the realtime events of #101)

    @Test func aCommentFromElsewhereIsInsertedInOrderOrReplacesTheKnownOne() async {
        let repository = FakeActivityCommentRepository()
        let first = ActivityComment.fixture(body: "Un", createdAt: at(0))
        let third = ActivityComment.fixture(body: "Trois", createdAt: at(120))
        var countChanges: [Int] = []
        let store = await loadedStore(repository, [first, third]) { countChanges.append($0) }

        let second = ActivityComment.fixture(body: "Deux", createdAt: at(60))
        #expect(!store.knows(second.id))
        store.receive(second)
        #expect(store.knows(second.id))
        var edited = first
        edited.body = "Un, modifié"
        edited.updatedAt = at(200)
        store.receive(edited)
        // Its own echo, same state: nothing changes.
        store.receive(third)

        #expect(store.comments.map(\.comment) == [edited, second, third])
        #expect(countChanges == [1])
    }

    @Test func aCommentDeletedElsewhereGoes() async {
        let repository = FakeActivityCommentRepository()
        let mine = ActivityComment.fixture(mine: true)
        var countChanges: [Int] = []
        let store = await loadedStore(repository, [mine]) { countChanges.append($0) }
        store.startEditing(mine.id)

        store.remove(mine.id)
        store.remove(UUID())

        #expect(store.comments.isEmpty)
        #expect(store.editing == nil)
        #expect(countChanges == [-1])
    }

    // MARK: - Edit and delete

    private func loadedStore(
        _ repository: FakeActivityCommentRepository,
        _ items: [ActivityComment],
        onCountChange: @escaping @MainActor (Int) -> Void = { _ in }
    ) async -> ActivityCommentsStore {
        repository.setPage(.success(ActivityCommentsPage(items: items, previousCursor: nil)))
        let store = makeStore(repository, onCountChange: onCountChange)
        await store.load()
        return store
    }

    @Test func editingLoadsTheTextInTheComposerAndSendsThePatch() async {
        let repository = FakeActivityCommentRepository()
        let mine = ActivityComment.fixture(body: "Belle sortie", author: repository.author, mine: true)
        let store = await loadedStore(repository, [mine])

        store.startEditing(mine.id)
        #expect(store.editing == mine.id)
        #expect(store.draft == "Belle sortie")
        #expect(store.isComposerFocused)

        repository.holdNextWrite()
        store.draft = "Belle sortie au lac"
        let send = Task { await store.send() }
        #expect(await eventually { repository.isHoldingWrite })
        #expect(store.comments.first?.comment.body == "Belle sortie au lac")
        #expect(store.editing == nil)
        #expect(store.draft.isEmpty)

        repository.resume()
        await send.value
        #expect(repository.calls.last == .edit(mine.id, "Belle sortie au lac"))
        #expect(store.comments.first?.comment.updatedAt != nil)
        #expect(store.comments.count == 1)
        #expect(store.toast == nil)
    }

    @Test func aFailedEditGoesBackWithAToast() async {
        let repository = FakeActivityCommentRepository()
        repository.scriptEdit(.failure(.network))
        let mine = ActivityComment.fixture(body: "Belle sortie", author: repository.author, mine: true)
        let store = await loadedStore(repository, [mine])

        store.startEditing(mine.id)
        store.draft = "Autre chose"
        await store.send()

        #expect(store.comments.map(\.comment) == [mine])
        #expect(store.toast == "La modification n'a pas pu être enregistrée.")
    }

    @Test func cancellingAnEditEmptiesTheComposer() async {
        let repository = FakeActivityCommentRepository()
        let mine = ActivityComment.fixture(author: repository.author, mine: true)
        let store = await loadedStore(repository, [mine])

        store.startEditing(mine.id)
        store.cancelEditing()

        #expect(store.editing == nil)
        #expect(store.draft.isEmpty)
    }

    @Test func aDeleteAsksForConfirmationThenRemovesTheComment() async {
        let repository = FakeActivityCommentRepository()
        let first = ActivityComment.fixture(body: "Un", mine: true)
        let second = ActivityComment.fixture(body: "Deux")
        var countChanges: [Int] = []
        let store = await loadedStore(repository, [first, second]) { countChanges.append($0) }

        store.requestDeletion(first.id)
        #expect(store.pendingDeletion == first)
        #expect(repository.calls == [.page(before: nil)])

        repository.holdNextWrite()
        let delete = Task { await store.confirmDeletion() }
        #expect(await eventually { repository.isHoldingWrite })
        #expect(store.comments.map(\.comment) == [second])
        #expect(store.pendingDeletion == nil)
        #expect(countChanges == [-1])

        repository.resume()
        await delete.value
        #expect(repository.calls.last == .delete(first.id))
        #expect(store.comments.map(\.comment) == [second])
        #expect(countChanges == [-1])
    }

    @Test func aFailedDeleteGoesBackInPlaceWithAToast() async {
        let repository = FakeActivityCommentRepository()
        repository.scriptDelete(.failure(.server(code: "not_allowed_to_delete_comment")))
        let first = ActivityComment.fixture(body: "Un")
        let second = ActivityComment.fixture(body: "Deux", viewerCanDelete: true)
        let third = ActivityComment.fixture(body: "Trois")
        var countChanges: [Int] = []
        let store = await loadedStore(repository, [first, second, third]) { countChanges.append($0) }

        store.requestDeletion(second.id)
        await store.confirmDeletion()

        #expect(store.comments.map(\.comment) == [first, second, third])
        #expect(store.toast == "Le commentaire n'a pas pu être supprimé.")
        #expect(countChanges == [-1, 1])
    }
}
