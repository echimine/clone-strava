import Foundation
import Testing
@testable import StravaClone

@MainActor
struct FollowListStoreTests {
    private final class Changes {
        var received: [FollowCountsChange] = []
    }

    private func request(
        _ list: AthleteFollowsRequest.List = .followers,
        own: Bool = true,
        followers: Int = 12,
        following: Int = 8,
        pending: Int = 0
    ) -> AthleteFollowsRequest {
        AthleteFollowsRequest(
            profile: .fixture(
                id: "me",
                followerCount: followers,
                followingCount: following,
                viewerFollowStatus: own ? nil : FollowStatus.none,
                pendingFollowRequestCount: pending
            ),
            list: list
        )
    }

    private func makeStore(
        _ request: AthleteFollowsRequest,
        _ lists: FakeFollowListRepository,
        follows: FakeFollowRepository = FakeFollowRepository(),
        changes: Changes = Changes()
    ) -> FollowListStore {
        FollowListStore(
            request: request,
            loadList: LoadFollowList(repository: lists),
            removeFollower: RemoveFollower(repository: lists),
            follows: FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows)),
            requests: FollowRequestsStore(
                loadRequests: LoadFollowRequests(repository: lists),
                acceptRequest: AcceptFollowRequest(repository: lists),
                refuseRequest: RefuseFollowRequest(repository: lists)
            ),
            ownCountsChanged: { changes.received.append($0) }
        )
    }

    @Test func opensOnTheTappedListWithItsCountsAndFollowButtons() async {
        let lists = FakeFollowListRepository()
        lists.pages[.following] = [nil: .success(AthleteListPage(
            items: [.fixture("lea", "Léa Bernard", status: .accepted), .fixture("me", "Moi", status: nil)],
            nextCursor: nil
        ))]
        let store = makeStore(request(.following, own: false), lists)

        await store.load()
        await store.load()

        #expect(store.selected == .following)
        #expect(AthletesMessages.listTitle(.followers, count: store.followerCount) == "Abonnés · 12")
        #expect(AthletesMessages.listTitle(.following, count: store.followingCount) == "Abonnements · 8")
        #expect(store.items(of: .following).map(\.id) == ["lea", "me"])
        #expect(store.follows.status(of: "lea") == .accepted)
        #expect(store.follows.status(of: "me") == nil)
        #expect(lists.calls == [.list(.following, "me", cursor: nil)])
    }

    @Test func theOtherListLoadsWhenFirstShown() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("hugo", "Hugo Petit")], nextCursor: nil))]
        let store = makeStore(request(.following), lists)
        await store.load()

        await store.show(.followers)
        await store.show(.followers)

        #expect(store.selected == .followers)
        #expect(store.items(of: .followers).map(\.id) == ["hugo"])
        #expect(lists.calls == [.list(.following, "me", cursor: nil), .list(.followers, "me", cursor: nil)])
    }

    @Test func scrollingToTheEndLoadsTheNextPage() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [
            nil: .success(AthleteListPage(items: [.fixture("a", "A"), .fixture("b", "B")], nextCursor: "c2")),
            "c2": .success(AthleteListPage(items: [.fixture("c", "C")], nextCursor: nil)),
        ]
        let store = makeStore(request(), lists)
        await store.load()

        await store.loadMoreIfNeeded(current: .fixture("b", "B"))
        await store.loadMoreIfNeeded(current: .fixture("c", "C"))

        #expect(store.items(of: .followers).map(\.id) == ["a", "b", "c"])
        #expect(lists.calls.count == 2)
    }

    @Test func aFailedFirstPageSaysSo() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .failure(.offline)]
        let store = makeStore(request(), lists)

        await store.load()

        #expect(store.phase(of: .followers) == .failed(message: "Vous êtes hors ligne."))
    }

    @Test func theRequestsRowOnlyShowsOnMyFollowersWhenSomeoneAsks() {
        let lists = FakeFollowListRepository()

        #expect(makeStore(request(pending: 2), lists).showsRequestsRow)
        #expect(!makeStore(request(pending: 0), lists).showsRequestsRow)
        #expect(!makeStore(request(own: false, pending: 2), lists).showsRequestsRow)
        let following = makeStore(request(.following, pending: 2), lists)
        #expect(!following.showsRequestsRow)
    }

    @Test func acceptingARequestRemovesItAndAddsAFollower() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("hugo", "Hugo Petit")], nextCursor: nil))]
        lists.requestPages[nil] = .success(FollowRequestPage(items: [.fixture("lea", "Léa Bernard"), .fixture("zoe", "Zoé Roux")], nextCursor: nil))
        let changes = Changes()
        let store = makeStore(request(pending: 2), lists, changes: changes)
        await store.load()
        await store.requests.load()

        await store.requests.accept("lea")

        #expect(store.requests.items.map(\.id) == ["zoe"])
        #expect(store.followerCount == 13)
        #expect(store.pendingRequestCount == 1)
        #expect(store.items(of: .followers).map(\.id) == ["lea", "hugo"])
        #expect(store.follows.status(of: "lea") == FollowStatus.none)
        #expect(changes.received == [FollowCountsChange(followers: 1, pendingRequests: -1)])
        #expect(lists.calls.last == .accept("lea"))
    }

    @Test func refusingARequestOnlyRemovesIt() async {
        let lists = FakeFollowListRepository()
        lists.requestPages[nil] = .success(FollowRequestPage(items: [.fixture("lea", "Léa Bernard")], nextCursor: nil))
        let changes = Changes()
        let store = makeStore(request(pending: 1), lists, changes: changes)
        await store.requests.load()

        await store.requests.refuse("lea")

        #expect(store.requests.items.isEmpty)
        #expect(store.followerCount == 12)
        #expect(store.pendingRequestCount == 0)
        #expect(!store.showsRequestsRow)
        #expect(changes.received == [FollowCountsChange(pendingRequests: -1)])
    }

    @Test func aFailedAcceptPutsTheRequestBackWithAToast() async {
        let lists = FakeFollowListRepository()
        lists.requestPages[nil] = .success(FollowRequestPage(items: [.fixture("lea", "Léa Bernard")], nextCursor: nil))
        lists.acceptResult = .failure(.network)
        let changes = Changes()
        let store = makeStore(request(pending: 1), lists, changes: changes)
        await store.requests.load()

        await store.requests.accept("lea")

        #expect(store.requests.items.map(\.id) == ["lea"])
        #expect(store.requests.toast == "La demande n'a pas pu être acceptée, réessayez.")
        #expect(store.followerCount == 12)
        #expect(changes.received.isEmpty)
    }

    @Test func aRequestCancelledMeanwhileGoesAway() async {
        let lists = FakeFollowListRepository()
        lists.requestPages[nil] = .success(FollowRequestPage(items: [.fixture("lea", "Léa Bernard")], nextCursor: nil))
        lists.acceptResult = .failure(.notFound)
        let store = makeStore(request(pending: 1), lists)
        await store.requests.load()

        await store.requests.accept("lea")

        #expect(store.requests.items.isEmpty)
        #expect(store.followerCount == 12)
        #expect(store.pendingRequestCount == 0)
    }

    @Test func removingAFollowerTakesThemOffTheList() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("lea", "Léa"), .fixture("hugo", "Hugo")], nextCursor: nil))]
        let changes = Changes()
        let store = makeStore(request(), lists, changes: changes)
        await store.load()

        await store.removeFollower("lea")

        #expect(store.items(of: .followers).map(\.id) == ["hugo"])
        #expect(store.followerCount == 11)
        #expect(changes.received == [FollowCountsChange(followers: -1)])
        #expect(lists.calls.last == .remove("lea"))
    }

    @Test func aFailedRemovalPutsTheFollowerBack() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("lea", "Léa"), .fixture("hugo", "Hugo")], nextCursor: nil))]
        lists.removeResult = .failure(.offline)
        let changes = Changes()
        let store = makeStore(request(), lists, changes: changes)
        await store.load()

        await store.removeFollower("hugo")

        #expect(store.items(of: .followers).map(\.id) == ["lea", "hugo"])
        #expect(store.followerCount == 12)
        #expect(store.toast == "Vous êtes hors ligne.")
        #expect(changes.received.isEmpty)
    }

    @Test func onlyMyOwnFollowersCanBeRemoved() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("lea", "Léa")], nextCursor: nil))]
        let store = makeStore(request(own: false), lists)
        await store.load()

        await store.removeFollower("lea")

        #expect(!store.canRemoveFollowers)
        #expect(store.items(of: .followers).map(\.id) == ["lea"])
    }

    @Test func followingSomeoneFromMyListsCountsThem() async {
        let lists = FakeFollowListRepository()
        lists.pages[.followers] = [nil: .success(AthleteListPage(items: [.fixture("lea", "Léa")], nextCursor: nil))]
        let store = makeStore(request(), lists)
        await store.load()

        await store.follows.follow("lea")
        #expect(store.followingCount == 9)

        await store.follows.unfollow("lea")
        #expect(store.followingCount == 8)
    }
}
