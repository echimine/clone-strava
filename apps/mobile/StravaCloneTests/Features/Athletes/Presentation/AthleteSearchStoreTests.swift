import Foundation
import Testing
@testable import StravaClone

@MainActor
struct AthleteSearchStoreTests {
    private func makeStore(
        _ search: FakeAthleteSearchRepository,
        sleeper: ManualSleeper? = nil
    ) -> AthleteSearchStore {
        let follows = FakeFollowRepository()
        return AthleteSearchStore(
            searchAthletes: SearchAthletes(repository: search),
            follows: FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows)),
            sleep: sleeper?.sleep ?? { @Sendable _ in }
        )
    }

    @Test func showsTheResultsWithTheirFollowButtons() async {
        let search = FakeAthleteSearchRepository()
        search.results["léa"] = .success([.fixture("lea", "Léa Bernard"), .fixture("leo", "Léo Petit", status: .accepted)])
        let store = makeStore(search)

        await store.updateQuery(" léa ")?.value

        #expect(store.phase == .loaded)
        #expect(store.results.map(\.id) == ["lea", "leo"])
        #expect(store.follows.status(of: "lea") == FollowStatus.none)
        #expect(store.follows.status(of: "leo") == .accepted)
        #expect(search.queries == ["léa"])
    }

    @Test func sendsNothingUnderTwoLetters() async {
        let search = FakeAthleteSearchRepository()
        let store = makeStore(search)

        #expect(store.updateQuery("L") == nil)
        #expect(store.updateQuery("  é ") == nil)

        #expect(store.phase == .idle)
        #expect(search.queries.isEmpty)
    }

    @Test func waitsForTheTypingToPauseBeforeSearching() async {
        let search = FakeAthleteSearchRepository()
        let sleeper = ManualSleeper()
        let store = makeStore(search, sleeper: sleeper)

        store.updateQuery("Lé")
        let last = store.updateQuery("Léa")
        #expect(await eventually { sleeper.waiting == 1 })
        sleeper.wakeAll()
        await last?.value

        #expect(search.queries == ["Léa"])
        #expect(sleeper.requested.allSatisfy { $0 == .milliseconds(300) })
    }

    @Test func aNewQueryCancelsTheRequestInFlight() async {
        let search = FakeAthleteSearchRepository()
        let (gate, open) = AsyncStream<Void>.makeStream()
        search.gate = gate
        search.results["Lé"] = .success([.fixture("leo", "Léo Petit")])
        search.results["Léa"] = .success([.fixture("lea", "Léa Bernard")])
        let store = makeStore(search)

        let first = store.updateQuery("Lé")
        #expect(await eventually { search.queries == ["Lé"] })
        let second = store.updateQuery("Léa")
        #expect(await eventually { search.queries == ["Lé", "Léa"] })
        open.yield()
        open.yield()
        await first?.value
        await second?.value

        #expect(search.cancelled == ["Lé"])
        #expect(store.results.map(\.id) == ["lea"])
        #expect(store.phase == .loaded)
    }

    @Test func clearingTheFieldDropsTheResultsAndTheRequestInFlight() async {
        let search = FakeAthleteSearchRepository()
        let (gate, open) = AsyncStream<Void>.makeStream()
        search.results["Léa"] = .success([.fixture("lea", "Léa Bernard")])
        let store = makeStore(search)
        await store.updateQuery("Léa")?.value

        search.gate = gate
        let pending = store.updateQuery("Léa B")
        #expect(await eventually { search.queries.count == 2 })
        store.updateQuery("")
        open.yield()
        await pending?.value

        #expect(store.phase == .idle)
        #expect(store.results.isEmpty)
        #expect(search.cancelled == ["Léa B"])
    }

    @Test func aFailedSearchSaysSo() async {
        let search = FakeAthleteSearchRepository()
        search.results["Léa"] = .failure(.offline)
        let store = makeStore(search)

        await store.updateQuery("Léa")?.value

        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))
    }

    @Test func noMatchIsEmpty() async {
        let search = FakeAthleteSearchRepository()
        let store = makeStore(search)

        await store.updateQuery("Zoé")?.value

        #expect(store.isEmpty)
    }
}
