import Foundation
import Testing
@testable import StravaClone

/// « Résultats » of the detail (spec #252): loaded with the detail, reloaded with it (on
/// `activity.segments_matched` too), and the author's « Retirer ce temps de mes meilleurs efforts ».
@MainActor
struct ActivityResultsStoreTests {
    private func makeStore(
        _ repository: FakeActivityResultsRepository,
        id: ActivityID,
        analytics: FakeAnalyticsClient = FakeAnalyticsClient(),
        onRemoved: @escaping @MainActor () async -> Void = {}
    ) -> ActivityResultsStore {
        ActivityResultsStore(
            id: id,
            loadResults: LoadActivityResults(repository: repository),
            removeBestEffort: RemoveBestEffort(repository: repository),
            analytics: analytics,
            onRemoved: onRemoved
        )
    }

    private func detailStore(
        _ detail: ActivityDetail,
        results: ActivityResultsStore,
        events: FakeActivityEventSource? = nil
    ) -> ActivityDetailStore {
        let repository = FakeActivityDetailRepository(.success(detail))
        let kudos = FakeActivityKudosRepository()
        let changes = ActivityChanges()
        return ActivityDetailStore(
            id: detail.id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            updateActivity: UpdateActivity(repository: repository),
            deleter: .over(repository, changes: changes),
            events: events,
            results: results
        )
    }

    @Test func aFailedReloadKeepsWhatIsShown() async {
        let id = ActivityID()
        let shown = ActivityResults(matchingInProgress: false, poolLength: nil, bestEfforts: [.fixture()], efforts: [])
        let store = makeStore(FakeActivityResultsRepository(.success(shown), .failure(.network)), id: id)

        await store.load()
        await store.load()

        #expect(store.results == shown)
    }

    /// The detail's load (its first appearance, any reload) brings « Résultats » along.
    @Test func theDetailLoadsItsResults() async {
        let detail = ActivityDetail.fixture()
        let repository = FakeActivityResultsRepository(.success(.empty))
        let results = makeStore(repository, id: detail.id)

        await detailStore(detail, results: results).load()

        #expect(repository.requestedIds == [detail.id])
        #expect(results.results == .empty)
    }

    /// `activity.segments_matched` reads as an update (ADR-039 §14): the open detail reloads
    /// « Résultats », the Segments are there.
    @Test func anUpdateOfTheOpenActivityReloadsTheResults() async {
        let detail = ActivityDetail.fixture()
        let matched = ActivityResults(matchingInProgress: false, poolLength: nil, bestEfforts: [], efforts: [.fixture(medal: .gold)])
        let matching = ActivityResults(matchingInProgress: true, poolLength: nil, bestEfforts: [], efforts: [])
        let repository = FakeActivityResultsRepository(.success(matching), .success(matched))
        let results = makeStore(repository, id: detail.id)
        let events = FakeActivityEventSource()
        let store = detailStore(detail, results: results, events: events)
        await store.load()
        let observing = Task { await store.observeEvents() }
        defer { observing.cancel() }

        #expect(await eventually { events.subscriberCount == 1 })
        events.send(.updated(detail.id))

        #expect(await eventually { results.results == matched })
    }

    @Test func removingABestEffortTellsTheServerReloadsAndIsCounted() async {
        let id = ActivityID()
        let before = ActivityResults(
            matchingInProgress: false,
            poolLength: nil,
            bestEfforts: [.fixture(distanceM: 400, medal: .gold), .fixture(distanceM: 21_097.5, medal: .silver)],
            efforts: []
        )
        let after = ActivityResults(matchingInProgress: false, poolLength: nil, bestEfforts: [.fixture(distanceM: 400, medal: .gold)], efforts: [])
        let repository = FakeActivityResultsRepository(.success(before), .success(after))
        let analytics = FakeAnalyticsClient()
        var detailReloads = 0
        let store = makeStore(repository, id: id, analytics: analytics) { detailReloads += 1 }
        await store.load()

        await store.remove(before.bestEfforts[1])

        #expect(repository.removals == [.init(id: id, distanceM: 21_097.5)])
        #expect(store.results == after)
        #expect(analytics.events == [.bestEffortRemoved(distanceM: 21_097.5)])
        #expect(analytics.events.first?.properties == ["distance": .double(21_097.5)])
        // « Performances » of the card changed too.
        #expect(detailReloads == 1)
    }

    @Test func aFailedRemovalSaysSoAndKeepsTheTime() async {
        let id = ActivityID()
        let shown = ActivityResults(matchingInProgress: false, poolLength: nil, bestEfforts: [.fixture(medal: .gold)], efforts: [])
        let repository = FakeActivityResultsRepository(.success(shown))
        repository.removeResult = .failure(.offline)
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, id: id, analytics: analytics)
        await store.load()

        await store.remove(shown.bestEfforts[0])

        #expect(store.results == shown)
        #expect(store.notice == "Vous êtes hors ligne.")
        #expect(analytics.events.isEmpty)
    }
}
