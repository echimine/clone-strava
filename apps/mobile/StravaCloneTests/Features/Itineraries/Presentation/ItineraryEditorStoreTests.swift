import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ItineraryEditorStoreTests {
    // Along a meridian, 0.001° of latitude is 111.195 m; points on the fake network's grid.
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.120)
    private let c = Coordinate(latitude: 45.910, longitude: 6.120)

    private func makeStore(sport: ItinerarySport = .run, router: FakeItineraryRouter) -> ItineraryEditorStore {
        ItineraryEditorStore(editor: ItineraryEditor(sport: sport, router: router))
    }

    @Test func statsCardShowsTheSportAndTheDistanceUpdatedOnEachTap() async {
        let router = FakeItineraryRouter()
        let store = makeStore(sport: .ride, router: router)
        #expect(store.sportLabel == "Vélo")
        #expect(store.distanceText == "0 m")

        store.tap(at: a)
        #expect(store.distanceText == "0 m")

        store.tap(at: b)
        await store.editor.settle()
        #expect(store.distanceText == "111 m")

        store.tap(at: c)
        await store.editor.settle()
        #expect(store.distanceText == "1,11 km")
    }

    @Test func markersShowTheStartThenTheFinishAtTheLastWaypoint() async {
        let store = makeStore(router: FakeItineraryRouter())

        store.tap(at: a)
        #expect(store.markers.map(\.role) == [.start])

        store.tap(at: b)
        store.tap(at: c)
        await store.editor.settle()
        #expect(store.markers.map(\.role) == [.start, .waypoint, .finish])
        #expect(store.markers.map(\.coordinate) == [a, b, c])
    }

    @Test func aLegIsDrawnDashedUntilItsPathIsComputed() async {
        let router = FakeItineraryRouter()
        await router.hold()
        let store = makeStore(router: router)

        store.tap(at: a)
        store.tap(at: b)
        await router.waitForCalls(1)
        #expect(store.lines.map(\.isProvisional) == [true])

        await router.release()
        await store.editor.settle()
        #expect(store.lines.map(\.isProvisional) == [false])
    }

    @Test func explainsAStraightLineFallbackUntilDismissed() async {
        let router = FakeItineraryRouter()
        await router.fail(with: .noPath)
        let store = makeStore(router: router)
        #expect(store.message == nil)

        store.tap(at: a)
        store.tap(at: b)
        await store.editor.settle()
        #expect(store.message == "Aucun chemin trouvé près de ce point : le tronçon passe en ligne droite.")

        store.dismissMessage()
        #expect(store.message == nil)
    }

    @Test func guidesTheFirstTaps() {
        let store = makeStore(router: FakeItineraryRouter())
        #expect(store.hint == "Touchez la carte pour placer le départ.")

        store.tap(at: a)
        #expect(store.hint == "Touchez la carte pour ajouter un point de passage.")
    }
}
