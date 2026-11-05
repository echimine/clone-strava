import Foundation
import Testing
@testable import StravaClone

/// The Leaderboard screen (ADR-039 §8, §9, §15) through `LeaderboardStore`: the chips, the
/// locks that open the Paywall in a sheet, the pages and `leaderboard_viewed`.
@MainActor
struct LeaderboardStoreTests {
    private let repository = FakeSegmentRepository()
    private let analytics = FakeAnalyticsClient()

    private func makeStore() -> LeaderboardStore {
        LeaderboardStore(segmentID: "seg-1", repository: repository, analytics: analytics)
    }

    @Test func opensOnTousAndIsViewed() async {
        let store = makeStore()

        await store.appeared()

        #expect(store.leaderboard == .sample())
        #expect(repository.calls == [.leaderboard("seg-1", LeaderboardSelection(), cursor: nil)])
        #expect(analytics.events == [.leaderboardViewed(filter: .all)])
    }

    @Test func withoutPremiumEveryLockOpensThePaywallAsOftenAsTapped() async {
        let store = makeStore()
        await store.appeared()

        store.tap(.female)
        #expect(store.paywall?.entry == .leaderboardFilter)
        store.paywallClosed()
        store.tap(.period(.week))
        #expect(store.paywall?.entry == .leaderboardFilter)
        store.paywallClosed()
        store.tapPremiumInsert()
        #expect(store.paywall?.entry == .segmentLeaderboard)

        #expect(store.selection == LeaderboardSelection())
        #expect(repository.calls.count == 1)
        #expect(store.isLocked(.female))
        #expect(!store.isLocked(.all))
    }

    @Test func withPremiumAChipReplacesTheFilterAndTappingItAgainRemovesIt() async {
        repository.leaderboardResults = [nil: .success(.sample(limited: false))]
        let store = makeStore()
        await store.appeared()

        await store.select(.period(.week))
        #expect(store.selection == LeaderboardSelection(gender: .all, filter: .period(.week)))
        await store.select(.following)
        #expect(store.selection == LeaderboardSelection(gender: .all, filter: .following))
        await store.select(.female)
        await store.select(.following)

        #expect(store.selection == LeaderboardSelection(gender: .female, filter: nil))
        #expect(repository.calls.last == .leaderboard("seg-1", LeaderboardSelection(gender: .female), cursor: nil))
        #expect(analytics.events.map(\.properties) == [
            ["filter": "all"], ["filter": "period"], ["filter": "following"], ["filter": "following"], ["filter": "female"],
        ])
        #expect(store.paywall == nil)
    }

    @Test func aPremiumThatExpiredFallsBackToTousAndOffersThePaywall() async {
        repository.leaderboardResults = [nil: .success(.sample(limited: false))]
        let store = makeStore()
        await store.appeared()
        repository.leaderboardResults = [nil: .failure(.premiumRequired)]

        await store.select(.male)

        #expect(store.paywall?.entry == .leaderboardFilter)
        #expect(store.selection == LeaderboardSelection())
    }

    @Test func readsTheNextPageAtTheEnd() async {
        repository.leaderboardResults = [
            nil: .success(.sample(limited: false, entries: [.line(1, "ann")], nextCursor: "c1")),
            "c1": .success(.sample(limited: false, entries: [.line(2, "bob")], nextCursor: nil)),
        ]
        let store = makeStore()
        await store.appeared()

        await store.loadMore()
        await store.loadMore()

        #expect(store.leaderboard?.entries.map(\.rank) == [1, 2])
        #expect(store.leaderboard?.nextCursor == nil)
        #expect(repository.calls.count == 2)
    }
}
