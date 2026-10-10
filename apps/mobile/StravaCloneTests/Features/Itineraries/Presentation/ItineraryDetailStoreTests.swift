import Foundation
import Testing
@testable import StravaClone

/// The detail screen reads the cache only (ADR-008 §1, ADR-030 §8): offline it shows any
/// prefetched Itinerary, it fetches a detail not prefetched yet, and it closes once the
/// Itinerary is gone.
@MainActor
struct ItineraryDetailStoreTests {
    private func make(
        _ id: ItineraryID = .fixture(1),
        analytics: FakeAnalyticsClient = FakeAnalyticsClient(),
        isOnline: Bool = true
    ) throws -> (ItineraryDetailStore, FakeItineraryRepository, GRDBItineraryCache) {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache)
        let store = ItineraryDetailStore(
            id: id,
            cache: cache,
            synchronizer: synchronizer,
            source: .profile,
            analytics: analytics,
            isOnline: { isOnline }
        )
        return (store, repository, cache)
    }

    /// `itinerary_viewed` (issue #20): once per opening, even if the screen shows again
    /// (back from the editor), with whether it was shown offline.
    @Test func openingTheDetailIsSentOnceWithItsSourceAndWhetherOffline() async throws {
        let analytics = FakeAnalyticsClient()
        let (store, _, cache) = try make(analytics: analytics, isOnline: false)
        try await cache.save(.fixture(1, name: "Tour du lac"), mapPolyline: EncodedPolyline(value: "local"))

        for _ in 0 ..< 2 {
            let observing = Task { await store.observe() }
            await waitUntil { store.detail != nil }
            observing.cancel()
            await observing.value
        }

        #expect(analytics.events == [.itineraryViewed(itineraryId: ItineraryID.fixture(1).description, source: .profile, offline: true)])
    }

    /// Waits for the store to reach `condition`, failing after about two seconds.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition never met", sourceLocation: sourceLocation)
    }

    @Test func offlineAPrefetchedDetailShowsItsTrackAndProfileFromTheCache() async throws {
        let (store, repository, cache) = try make()
        try await cache.save(.fixture(1, name: "Tour du lac"), mapPolyline: EncodedPolyline(value: "local"))

        let observing = Task { await store.observe() }
        await waitUntil { store.detail != nil }
        observing.cancel()

        #expect(store.detail == .fixture(1, name: "Tour du lac"))
        #expect(store.profile?.points.map(\.altitude) == [446.5, 480, 534])
        #expect(store.trackMessage == nil)
        #expect(repository.detailCalls.isEmpty)
    }

    @Test func aDetailNotPrefetchedYetIsFetchedOnOpening() async throws {
        let (store, repository, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1)])
        repository.setDetail(.success(.fixture(1)), for: .fixture(1))

        let observing = Task { await store.observe() }
        await waitUntil { store.detail != nil }
        observing.cancel()

        #expect(repository.detailCalls == [.fixture(1)])
        #expect(store.detail?.track == ItineraryDetail.fixture(1).track)
    }

    @Test func offlineADetailNeverFetchedShowsTheListedFiguresAndSaysTheTrackIsMissing() async throws {
        let (store, _, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1, name: "Col du Galibier")])

        let observing = Task { await store.observe() }
        await waitUntil { store.trackMessage != nil }
        observing.cancel()

        #expect(store.summary?.name == "Col du Galibier")
        #expect(store.detail == nil)
        #expect(store.trackMessage == ItineraryMessages.trackUnavailableOffline)
        #expect(!store.isGone)
    }

    @Test func aDetailUpdatedElsewhereIsReplacedWhenItArrives() async throws {
        let (store, repository, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        try await cache.replaceSummaries(with: [.fixture(1, updatedMinutes: 5)])
        repository.setDetail(.success(.fixture(1, name: "Modifié", updatedMinutes: 5)), for: .fixture(1))

        let observing = Task { await store.observe() }
        await waitUntil { store.detail?.name == "Modifié" }
        observing.cancel()

        #expect(store.detail?.updatedAt == .fixture(minutes: 5))
    }

    @Test func aDetailNotFoundClosesTheScreenAndForgetsTheItinerary() async throws {
        let (store, repository, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1)])
        repository.setDetail(.failure(.notFound), for: .fixture(1))

        let observing = Task { await store.observe() }
        await waitUntil { store.isGone }
        observing.cancel()

        #expect(try await cache.summaries(limit: 20).isEmpty)
    }

    @Test func anItineraryDeletedWhileOpenClosesTheScreen() async throws {
        let (store, _, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        let observing = Task { await store.observe() }
        await waitUntil { store.detail != nil }

        try await cache.delete(id: .fixture(1))

        await waitUntil { store.isGone }
        observing.cancel()
    }

    @Test func theGainIsApproximateOutsideIGNAndTheSourceIsCredited() async throws {
        let (store, _, cache) = try make()
        try await cache.save(.fixture(1, elevationSource: .mixed), mapPolyline: EncodedPolyline(value: "local"))

        let observing = Task { await store.observe() }
        await waitUntil { store.detail != nil }
        observing.cancel()

        #expect(store.distanceText == "2,22 km")
        #expect(store.elevationText == "≈ 88 m")
        #expect(store.elevationSourceText == "Altitudes : IGN, Open-Meteo / Copernicus")
    }

    @Test func withIGNAltitudesTheGainIsExact() async throws {
        let (store, _, cache) = try make()
        try await cache.save(.fixture(1, elevationSource: .ign), mapPolyline: EncodedPolyline(value: "local"))

        let observing = Task { await store.observe() }
        await waitUntil { store.detail != nil }
        observing.cancel()

        #expect(store.elevationText == "88 m")
        #expect(store.elevationSourceText == "Altitudes : IGN")
    }
}
