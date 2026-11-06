import Foundation
import SwiftUI
import Testing
@testable import StravaClone

/// The feed and the Activity detail (ADR-033 §1, §7): only processed cards open the detail,
/// and the cards follow what the detail publishes on the Core change stream.
@MainActor
struct FeedStoreActivityDetailTests {
    private func makeStore(
        _ repository: FakeFeedRepository,
        local: FakeLocalActivityFeedSource = FakeLocalActivityFeedSource(),
        changes: ActivityChanges = ActivityChanges()
    ) -> FeedStore {
        FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            loadRecentKudos: LoadRecentKudos(repository: repository),
            events: FakeFeedEventSource(),
            localActivities: local,
            activityChanges: changes
        )
    }

    @Test func aProcessedCardOpensTheDetailButALocalCardDoesNot() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture(status: .processing, state: .processing)
        let store = makeStore(repository, local: local)
        local.send([card])
        let observation = Task { await store.observeLocalActivities() }
        while store.localCards.isEmpty { await Task.yield() }
        await store.refresh()

        store.open(card.id)
        #expect(store.path.isEmpty)

        store.open(post.id)
        #expect(store.path == NavigationPath([ActivityDetailRequest(id: post.id)]))
        observation.cancel()
    }

    /// The card's comment button opens the Kudos and comments screen on Commentaires, the
    /// composer focused (ADR-036 §8); a local card has none.
    @Test func theCommentButtonOpensTheCommentsWithTheComposerFocused() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = makeStore(repository)
        await store.refresh()

        store.openComments(ActivityID())
        #expect(store.path.isEmpty)

        store.openComments(post.id)
        let expected = ActivityEngagementRequest(activityId: post.id, tab: .comments, focusComposer: true)
        #expect(store.path == NavigationPath([expected]))
    }

    /// The 👍 of my own card: the Kudos and comments screen on Kudos, no composer.
    @Test func theKudosButtonOfMyCardOpensTheKudos() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = makeStore(repository)
        await store.refresh()

        store.openKudos(ActivityID())
        #expect(store.path.isEmpty)

        store.openKudos(post.id)
        #expect(store.path == NavigationPath([ActivityEngagementRequest.kudos(post.id)]))
    }

    /// The home's magnifier pushes the athlete search.
    @Test func theMagnifierOpensTheAthleteSearch() {
        let store = makeStore(FakeFeedRepository())
        store.openSearch()
        #expect(store.path == NavigationPath([AthleteSearchRequest()]))
    }

    @Test func theCardsFollowWhatTheDetailPublishes() async {
        let repository = FakeFeedRepository()
        let edited = ActivityPost.fixture()
        let deleted = ActivityPost.fixture()
        let commented = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [edited, deleted, commented], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.refresh()

        let renamed = ActivityPost.fixture(id: edited.id, title: "Sortie vélo", sport: .ride)
        let engagement = ActivityEngagement(kudosCount: 7, commentCount: 3, viewerHasKudoed: true)
        changes.publish(.updated(renamed))
        changes.publish(.deleted(deleted.id))
        changes.publish(.engagement(commented.id, engagement))
        // Unknown to the feed: ignored, never added.
        changes.publish(.updated(.fixture()))

        #expect(await eventually { store.posts.last?.engagement == engagement })
        #expect(store.posts.map(\.id) == [edited.id, commented.id])
        #expect(store.posts.first == renamed)
    }

    /// ADR-038 §8: once an athlete is blocked, every card of theirs leaves the feed.
    @Test func aBlockedAthletesCardsLeaveTheFeed() async {
        let repository = FakeFeedRepository()
        let blocked = ActivityAuthor(id: "u9", displayName: "Tom Bloqué", avatarURL: nil)
        let theirs = [ActivityPost.fixture(author: blocked), ActivityPost.fixture(author: blocked)]
        let kept = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [theirs[0], kept, theirs[1]], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.refresh()

        changes.publish(.authorHidden(athleteId: blocked.id))

        #expect(await eventually { store.posts.map(\.id) == [kept.id] })
    }

    /// The detail does not know the card's kudos avatars nor whether the route was trimmed
    /// (ADR-036 §5): an edit keeps the card's.
    @Test func anEditFromTheDetailKeepsTheAvatarsAndTheMaskedLabel() async {
        let repository = FakeFeedRepository()
        let giver = ActivityAuthor(id: "u2", displayName: "Léa Bernard", avatarURL: nil)
        let post = ActivityPost.fixture(routeTrimmed: true, recentKudos: [giver])
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.refresh()

        changes.publish(.updated(ActivityPost.fixture(id: post.id, title: "Sortie vélo")))

        #expect(await eventually { store.posts.first?.title == "Sortie vélo" })
        #expect(store.posts.first?.recentKudos == [giver])
        #expect(store.posts.first?.routeTrimmed == true)
    }

    /// A kudos given on the detail changes the count: the card reloads its avatars too.
    @Test func aKudosFromTheDetailReloadsTheAvatars() async {
        let repository = FakeFeedRepository()
        let viewer = ActivityAuthor(id: "u3", displayName: "Hugo Petit", avatarURL: nil)
        let kudoed = ActivityPost.fixture(kudos: 0)
        let commented = ActivityPost.fixture(kudos: 0)
        repository.pages[nil] = .success(FeedPage(posts: [kudoed, commented], nextCursor: nil))
        repository.recentKudosResult = .success([viewer])
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.refresh()

        changes.publish(.engagement(commented.id, ActivityEngagement(kudosCount: 0, commentCount: 1, viewerHasKudoed: false)))
        changes.publish(.engagement(kudoed.id, ActivityEngagement(kudosCount: 1, commentCount: 0, viewerHasKudoed: true)))

        #expect(await eventually { store.posts.first?.recentKudos == [viewer] })
        #expect(store.posts.first?.engagement.kudosCount == 1)
        #expect(repository.recentKudosCalls == [kudoed.id])
    }

    /// ADR-033 §1: the long-press menu ("Modifier") is only on my processed cards, never on
    /// another athlete's card or on a local card.
    @Test func onlyMyProcessedCardsHaveTheManageMenu() async {
        let repository = FakeFeedRepository()
        let mine = ActivityPost.fixture(viewerIsAuthor: true)
        let theirs = ActivityPost.fixture(viewerIsAuthor: false)
        repository.pages[nil] = .success(FeedPage(posts: [mine, theirs], nextCursor: nil))
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture(status: .processing, state: .processing)
        let store = makeStore(repository, local: local)
        local.send([card])
        let observation = Task { await store.observeLocalActivities() }
        while store.localCards.isEmpty { await Task.yield() }
        await store.refresh()

        #expect(store.canManage(mine.id))
        #expect(!store.canManage(theirs.id))
        #expect(!store.canManage(card.id))
        observation.cancel()
    }
}
