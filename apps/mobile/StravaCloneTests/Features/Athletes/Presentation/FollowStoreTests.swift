import Foundation
import Testing
@testable import StravaClone

@MainActor
struct FollowStoreTests {
    private func makeStore(_ follows: FakeFollowRepository) -> FollowStore {
        FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows))
    }

    @Test func followingShowsAbonneAtOnceThenTheServersAnswer() async {
        let follows = FakeFollowRepository()
        follows.followResult = .success(.pending)
        let (gate, open) = AsyncStream<Void>.makeStream()
        follows.gate = gate
        let store = makeStore(follows)
        store.track("lea", status: FollowStatus.none)

        let tap = Task { await store.follow("lea") }
        while follows.calls.isEmpty { await Task.yield() }
        #expect(store.status(of: "lea") == .accepted)

        open.yield()
        let change = await tap.value
        #expect(store.status(of: "lea") == .pending)
        #expect(change?.status == .pending)
        #expect(store.toast == nil)
    }

    @Test func cancellingARequestOrUnfollowingGoesBackToSuivre() async {
        let follows = FakeFollowRepository()
        let store = makeStore(follows)
        store.track("lea", status: .pending)
        store.track("hugo", status: .accepted)

        await store.unfollow("lea")
        await store.unfollow("hugo")

        #expect(store.status(of: "lea") == FollowStatus.none)
        #expect(store.status(of: "hugo") == FollowStatus.none)
        #expect(follows.calls == [.unfollow("lea"), .unfollow("hugo")])
    }

    @Test func aFailedFollowRollsBackWithAToast() async {
        let follows = FakeFollowRepository()
        follows.followResult = .failure(.network)
        let store = makeStore(follows)
        store.track("lea", status: FollowStatus.none)

        let change = await store.follow("lea")

        #expect(change == nil)
        #expect(store.status(of: "lea") == FollowStatus.none)
        #expect(store.toast == "L'abonnement n'a pas abouti, réessayez.")
    }

    @Test func aFailedUnfollowRollsBackWithAToast() async {
        let follows = FakeFollowRepository()
        follows.unfollowResult = .failure(.offline)
        let store = makeStore(follows)
        store.track("lea", status: .accepted)

        await store.unfollow("lea")

        #expect(store.status(of: "lea") == .accepted)
        #expect(store.toast == "Vous êtes hors ligne.")
    }

    @Test func tapsWhileAChangeIsInFlightAreIgnored() async {
        let follows = FakeFollowRepository()
        let (gate, open) = AsyncStream<Void>.makeStream()
        follows.gate = gate
        let store = makeStore(follows)
        store.track("lea", status: FollowStatus.none)

        let tap = Task { await store.follow("lea") }
        while follows.calls.isEmpty { await Task.yield() }
        await store.unfollow("lea")
        await store.follow("lea")
        store.track("lea", status: FollowStatus.none)
        #expect(store.status(of: "lea") == .accepted)

        open.yield()
        await tap.value
        #expect(follows.calls == [.follow("lea")])
        #expect(store.status(of: "lea") == .accepted)
    }

    @Test func myselfHasNoButton() {
        let store = makeStore(FakeFollowRepository())
        store.track("me", status: nil)
        #expect(store.status(of: "me") == nil)
    }
}
