import Foundation
import Testing
@testable import StravaClone

/// Plus › « Segments » (ADR-039 §15): my favourite Segments, by pages.
@MainActor
struct FavoriteSegmentsStoreTests {
    @Test func loadsTheFirstPageThenTheNextOnesUntilTheLast() async {
        let repository = FakeFavoriteSegmentsRepository()
        await repository.serve(FavoriteSegmentsPage(items: [.fixture(1), .fixture(2)], nextCursor: "c1"))
        await repository.serve(FavoriteSegmentsPage(items: [.fixture(3)], nextCursor: nil), after: "c1")
        let store = FavoriteSegmentsStore(loadPage: LoadFavoriteSegments(repository: repository))

        await store.load()
        #expect(store.items.map(\.id) == ["segment-1", "segment-2"])
        #expect(store.canLoadMore)

        await store.loadMore()
        await store.loadMore()
        #expect(store.items.map(\.id) == ["segment-1", "segment-2", "segment-3"])
        #expect(!store.canLoadMore)
        #expect(await repository.requestedCursors == [nil, "c1"])
    }

    @Test func aRefreshStartsOverFromTheFirstPage() async {
        let repository = FakeFavoriteSegmentsRepository()
        await repository.serve(FavoriteSegmentsPage(items: [.fixture(1)], nextCursor: nil))
        let store = FavoriteSegmentsStore(loadPage: LoadFavoriteSegments(repository: repository))
        await store.load()

        await repository.serve(FavoriteSegmentsPage(items: [.fixture(4), .fixture(1)], nextCursor: nil))
        await store.load()

        #expect(store.items.map(\.id) == ["segment-4", "segment-1"])
    }

    @Test func offlineWithNothingLoadedSaysConnectionRequired() async {
        let repository = FakeFavoriteSegmentsRepository()
        await repository.fail(with: .offline)
        let store = FavoriteSegmentsStore(loadPage: LoadFavoriteSegments(repository: repository))

        await store.load()

        #expect(store.phase == .failed("Connexion requise"))
    }

    @Test func formatsARowAsDistanceGradeAndMyBestTime() {
        let row = FavoriteSegmentRow(segment: .fixture(2, best: .seconds(312)))
        #expect(row.figures == "2,00 km · 5,2 %")
        #expect(row.bestTime == "5 min 12 s")
        #expect(FavoriteSegmentRow(segment: .fixture(1)).bestTime == nil)
    }
}
