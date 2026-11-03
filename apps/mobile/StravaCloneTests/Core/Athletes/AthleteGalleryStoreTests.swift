import Foundation
import Testing
@testable import StravaClone

/// The profile's Galerie tab (ADR-037 §9, §10, §13), mine or another athlete's.
@MainActor
struct AthleteGalleryStoreTests {
    private func makeStore(
        _ repository: FakeAthleteGalleryRepository,
        analytics: FakeAnalyticsClient = FakeAnalyticsClient(),
        changes: ActivityChanges? = nil
    ) -> AthleteGalleryStore {
        AthleteGalleryStore(
            loadGallery: LoadAthleteGallery(repository: repository),
            message: { _ in "Impossible de charger la Galerie." },
            activityChanges: changes,
            analytics: analytics
        )
    }

    private func items(_ count: Int) -> [GalleryItem] {
        (0..<count).map { _ in .fixture() }
    }

    @Test func openingTheTabSaysSoEachTimeAndLoadsTheFirstPageOnce() async {
        let repository = FakeAthleteGalleryRepository()
        let first = items(3)
        repository.pages[nil] = .success(GalleryPage(items: first, nextCursor: nil))
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, analytics: analytics)

        await store.open(athleteId: "lea", isOwn: false)
        await store.open(athleteId: "lea", isOwn: false)

        #expect(store.phase == .loaded)
        #expect(store.items == first)
        #expect(repository.calls.map(\.cursor) == [nil])
        #expect(analytics.events == [.galleryViewed(isOwn: false), .galleryViewed(isOwn: false)])
    }

    @Test func scrollingNearTheEndLoadsTheNextPageOnce() async {
        let repository = FakeAthleteGalleryRepository()
        let first = items(12)
        let second = items(2)
        repository.pages[nil] = .success(GalleryPage(items: first, nextCursor: "c1"))
        repository.pages["c1"] = .success(GalleryPage(items: second, nextCursor: nil))
        let store = makeStore(repository)
        await store.open(athleteId: "me", isOwn: true)

        await store.loadMoreIfNeeded(current: first[0])
        #expect(repository.calls.map(\.cursor) == [nil])

        await store.loadMoreIfNeeded(current: first[11])
        await store.loadMoreIfNeeded(current: second[1])

        #expect(store.items == first + second)
        #expect(repository.calls.map(\.cursor) == [nil, "c1"])
        #expect(repository.calls.allSatisfy { $0.athleteId == "me" })
    }

    @Test func aFailedNextPageKeepsTheGridAndSaysSo() async {
        let repository = FakeAthleteGalleryRepository()
        let first = items(3)
        repository.pages[nil] = .success(GalleryPage(items: first, nextCursor: "c1"))
        let store = makeStore(repository)
        await store.open(athleteId: "me", isOwn: true)

        await store.loadMoreIfNeeded(current: first[2])

        #expect(store.items == first)
        #expect(store.notice == "Impossible de charger la Galerie.")
    }

    @Test func aFailedFirstPageSaysSoAndNoMediaIsEmpty() async {
        let repository = FakeAthleteGalleryRepository()
        repository.pages[nil] = .failure(.offline)
        let store = makeStore(repository)

        await store.open(athleteId: "me", isOwn: true)
        #expect(store.phase == .failed(message: "Impossible de charger la Galerie."))
        #expect(!store.isEmpty)

        repository.pages[nil] = .success(GalleryPage(items: [], nextCursor: nil))
        await store.refresh()
        #expect(store.isEmpty)
    }

    @Test func refreshingBeforeTheTabWasOpenedLoadsNothing() async {
        let repository = FakeAthleteGalleryRepository()
        let store = makeStore(repository)

        await store.refresh()

        #expect(repository.calls.isEmpty)
        #expect(store.phase == .idle)
    }

    @Test func aTapOpensTheViewerOverEveryLoadedMediaWithTheirActivities() async {
        let repository = FakeAthleteGalleryRepository()
        let run = ActivityID()
        let loaded = [GalleryItem.fixture(activity: run, title: "Footing"), .fixture(kind: .video), .fixture()]
        repository.pages[nil] = .success(GalleryPage(items: loaded, nextCursor: nil))
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, analytics: analytics)
        await store.open(athleteId: "lea", isOwn: false)

        store.openMedia(loaded[1].media)

        let request = try? #require(store.mediaViewer)
        #expect(request?.mode == .gallery)
        #expect(request?.start == 1)
        #expect(request?.items.map(\.media) == loaded.map(\.media))
        #expect(request?.items.first?.activity == MediaViewerActivity(id: run, title: "Footing", startedAt: loaded[0].activity.startedAt))
        #expect(analytics.events.last == .mediaViewerOpened(source: .gallery, kind: .video, isOwn: false))
    }

    @Test func aDeletedActivityLeavesTheGrid() async {
        let repository = FakeAthleteGalleryRepository()
        let deleted = ActivityID()
        let kept = GalleryItem.fixture()
        repository.pages[nil] = .success(GalleryPage(items: [.fixture(activity: deleted), kept, .fixture(activity: deleted)], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.open(athleteId: "me", isOwn: true)

        changes.publish(.deleted(deleted))

        #expect(await eventually { store.items == [kept] })
    }

    @Test func signingOutForgetsTheGallery() async {
        let repository = FakeAthleteGalleryRepository()
        repository.pages[nil] = .success(GalleryPage(items: items(2), nextCursor: "c1"))
        let store = makeStore(repository)
        await store.open(athleteId: "me", isOwn: true)

        store.reset()

        #expect(store.items.isEmpty)
        #expect(store.phase == .idle)
    }
}
