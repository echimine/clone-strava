import Foundation
import Testing
@testable import StravaClone

/// Deleting a processed Activity (ADR-033 §7): online and optimistic. The card goes at once;
/// a failure brings it back where it was, with a toast.
@MainActor
struct ActivityDeleteTests {
    private let deleted = ActivityDetail.fixture(title: "Sortie du matin")
    private let other = ActivityDetail.fixture(title: "Sortie du soir")

    /// The feed showing `deleted`'s card above `other`'s, following `changes`.
    private func makeFeed(changes: ActivityChanges) async -> FeedStore {
        let repository = FakeFeedRepository()
        repository.pages[nil] = .success(FeedPage(posts: [deleted.post, other.post], nextCursor: nil))
        let feed = FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            activityChanges: changes
        )
        await feed.refresh()
        return feed
    }

    private func makeDeleter(_ repository: FakeActivityDetailRepository, changes: ActivityChanges) -> ActivityDeleter {
        ActivityDeleter(deleteActivity: DeleteActivity(repository: repository), changes: changes)
    }

    @Test func deletingACardRemovesItAtOnce() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(deleted))
        let (gate, release) = AsyncStream<Void>.makeStream()
        repository.deleteGate = gate
        let deleter = makeDeleter(repository, changes: changes)

        let deleting = Task { await deleter.delete(deleted.id) }

        // Gone before the server answers.
        #expect(await eventually { feed.posts == [other.post] })
        #expect(repository.deletedIds == [deleted.id])
        release.yield()
        await deleting.value
        #expect(feed.posts == [other.post])
        #expect(deleter.toast == nil)
    }

    @Test func aFailedDeleteBringsTheCardBackWithAToast() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(deleted))
        repository.deleteResult = .failure(.network)
        let deleter = makeDeleter(repository, changes: changes)

        await deleter.delete(deleted.id)

        #expect(await eventually { feed.posts == [deleted.post, other.post] })
        #expect(deleter.toast == "La suppression n'a pas pu être effectuée.")
    }

    /// `409 not_deletable`: the Activity is being processed (ADR-031 §14), the existing message.
    @Test func anActivityBeingProcessedComesBackWithTheExistingMessage() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(deleted))
        repository.deleteResult = .failure(.server(code: "not_deletable"))
        let deleter = makeDeleter(repository, changes: changes)

        await deleter.delete(deleted.id)

        #expect(await eventually { feed.posts == [deleted.post, other.post] })
        #expect(deleter.toast == "Suppression impossible : l'activité est déjà en traitement.")
    }

    /// `404`: deleted meanwhile, e.g. from another device. Nothing to undo.
    @Test func anActivityAlreadyGoneStaysGone() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let published = changes.subscribe()
        let repository = FakeActivityDetailRepository(.success(deleted))
        repository.deleteResult = .failure(.notFound)
        let deleter = makeDeleter(repository, changes: changes)

        await deleter.delete(deleted.id)

        #expect(await changes.published(on: published) == [.deleted(deleted.id)])
        #expect(feed.posts == [other.post])
        #expect(deleter.toast == nil)
    }

    /// From the detail: back to the feed, the card is gone, no toast (ADR-033 §7).
    @Test func deletingFromTheDetailRemovesTheCard() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(deleted))
        let deleter = makeDeleter(repository, changes: changes)
        let kudos = FakeActivityKudosRepository()
        let store = ActivityDetailStore(
            id: deleted.id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            deleter: deleter
        )
        await store.load()

        await store.delete()

        #expect(repository.deletedIds == [deleted.id])
        #expect(await eventually { feed.posts == [other.post] })
        #expect(deleter.toast == nil)
    }

    /// The toast of a failed delete from the detail shows over the feed, where the athlete is
    /// back: the detail uses the feed's deleter.
    @Test func aFailedDeleteFromTheDetailBringsTheCardBack() async {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(deleted))
        repository.deleteResult = .failure(.offline)
        let deleter = makeDeleter(repository, changes: changes)
        let kudos = FakeActivityKudosRepository()
        let store = ActivityDetailStore(
            id: deleted.id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            deleter: deleter
        )
        await store.load()

        await store.delete()

        #expect(await eventually { feed.posts == [deleted.post, other.post] })
        #expect(deleter.toast == "Vous êtes hors ligne : l'activité n'a pas été supprimée.")
    }
}
