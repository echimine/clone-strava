import Foundation
import Testing
@testable import StravaClone

/// The Segments mode of the Map tab (ADR-039 §15): the zone shown at opening, then fixed until
/// « Rechercher dans cette zone »; the sport and favourite filters; nothing under zoom 10.5;
/// cards sorted by distance to the zone's centre; the star in one tap.
@MainActor
struct SegmentMapStoreTests {
    private func make(
        analytics: FakeAnalyticsClient = FakeAnalyticsClient()
    ) -> (SegmentMapStore, FakeSegmentMapRepository, FakeSegmentRepository) {
        let repository = FakeSegmentMapRepository()
        let favorites = FakeSegmentRepository()
        let store = SegmentMapStore(
            searchSegments: SearchMapSegments(repository: repository),
            setFavorite: SetSegmentFavorite(repository: favorites),
            analytics: analytics
        )
        return (store, repository, favorites)
    }

    @Test func theFirstSettledCameraIsSearchedAndItsSegmentsSortedByDistanceToTheCentre() async {
        let (store, repository, _) = make()
        let area = MapArea.annecy()
        repository.segments = [
            .fixture("far", start: Coordinate(latitude: 45.915, longitude: 6.155)),
            .fixture("near", start: area.center),
        ]

        await store.cameraSettled(area)

        #expect(repository.searches == [.init(area: area, filter: SegmentMapFilter())])
        #expect(store.segments.map(\.id) == ["near", "far"])
        #expect(store.countLabel == "2 Segments dans cette zone")
    }

    @Test func theZoneStaysFixedUntilSearchedAgainAfterAMove() async {
        let (store, repository, _) = make()
        await store.cameraSettled(.annecy())
        #expect(!store.canSearchHere)

        let moved = MapArea.annecy(shiftedEastBy: 0.05)
        await store.cameraSettled(moved)

        #expect(repository.searches.count == 1)
        #expect(store.canSearchHere)

        await store.searchHere()

        #expect(repository.searches.last?.area == moved)
        #expect(!store.canSearchHere)
    }

    @Test func underZoomTenAndAHalfNothingIsSearchedNorShown() async {
        let (store, repository, _) = make()
        repository.segments = [.fixture("a")]

        await store.cameraSettled(.annecy(zoom: 10.2))

        #expect(repository.searches.isEmpty)
        #expect(store.isZoomedOut)
        #expect(store.visibleSegments.isEmpty)

        await store.cameraSettled(.annecy(zoom: 12))
        #expect(repository.searches.count == 1)
        #expect(store.visibleSegments.map(\.id) == ["a"])

        await store.cameraSettled(.annecy(zoom: 10))
        #expect(store.isZoomedOut)
        #expect(store.visibleSegments.isEmpty)
        #expect(!store.canSearchHere)
    }

    @Test func aSportAndTheFavouritesCombineAndSearchTheSameZoneAgain() async {
        let (store, repository, _) = make()
        let area = MapArea.annecy()
        repository.segments = [
            .fixture("ride"),
            .fixture("favoriteRide", isFavorite: true),
            .fixture("favoriteRun", sport: .run, isFavorite: true),
        ]
        await store.cameraSettled(area)
        // A move does not change the zone a filter searches.
        await store.cameraSettled(.annecy(shiftedEastBy: 0.05))

        await store.select(sport: .ride)
        #expect(store.segments.map(\.id).sorted() == ["favoriteRide", "ride"])

        await store.toggleFavoritesOnly()
        #expect(store.segments.map(\.id) == ["favoriteRide"])

        await store.select(sport: nil)
        #expect(store.segments.map(\.id).sorted() == ["favoriteRide", "favoriteRun"])
        #expect(repository.searches.map(\.area) == Array(repeating: area, count: 4))
        #expect(repository.searches.last?.filter == SegmentMapFilter(sport: nil, favoritesOnly: true))
    }

    @Test func theEmptyStateSaysWhetherFavouritesAreFiltered() async {
        let (store, _, _) = make()
        await store.cameraSettled(.annecy())
        #expect(store.emptyMessage == "Aucun Segment dans cette zone. Crée le premier !")

        await store.toggleFavoritesOnly()
        #expect(store.emptyMessage == "Aucun Segment favori dans cette zone.")
    }

    @Test func aCardAddedToFavoritesInOneTapIsSentAndCountedThenRemoved() async {
        let analytics = FakeAnalyticsClient()
        let (store, repository, favorites) = make(analytics: analytics)
        repository.segments = [.fixture("a")]
        await store.cameraSettled(.annecy())

        await store.toggleFavorite("a")
        #expect(store.segments.first?.isFavorite == true)

        await store.toggleFavorite("a")
        #expect(store.segments.first?.isFavorite == false)
        #expect(favorites.calls == [.setFavorite("a", true), .setFavorite("a", false)])
        #expect(analytics.events == [.segmentFavorited])
    }

    @Test func aStarTheServerRefusesIsTakenBackWithAMessage() async {
        let (store, repository, favorites) = make()
        repository.segments = [.fixture("a")]
        await store.cameraSettled(.annecy())
        favorites.favoriteResult = .failure(.server)

        await store.toggleFavorite("a")

        #expect(store.segments.first?.isFavorite == false)
        #expect(store.message == SegmentMapMessages.favoriteFailed)
    }

    @Test func scrollingToACardOrTappingItsPathHighlightsIt() async {
        let (store, repository, _) = make()
        repository.segments = [.fixture("a"), .fixture("b", start: Coordinate(latitude: 45.91, longitude: 6.15))]
        await store.cameraSettled(.annecy())
        #expect(store.focused == nil)

        store.focusedID = "b"

        #expect(store.focused?.id == "b")
        #expect(store.focusedPath == repository.segments[1].path)
    }

    @Test func offlineTheSearchSaysAConnectionIsNeededAndCanBeRetried() async {
        let (store, repository, _) = make()
        repository.error = .offline
        await store.cameraSettled(.annecy())

        #expect(store.failure == SegmentMapMessages.connectionRequired)
        #expect(store.canSearchHere)

        repository.error = nil
        repository.segments = [.fixture("a")]
        await store.searchHere()

        #expect(store.failure == nil)
        #expect(store.segments.map(\.id) == ["a"])
    }

    @Test func aZoneTheServerFindsTooLargeAsksToZoomIn() async {
        let (store, repository, _) = make()
        repository.error = .zoneTooLarge

        await store.cameraSettled(.annecy())

        #expect(store.isZoomedOut)
        #expect(store.failure == nil)
    }
}
