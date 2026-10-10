import Foundation
import Testing
@testable import StravaClone

/// The elevation gain in the stats card (ADR-030 §3): approximate with "≈" and credited
/// to its altitude source, greyed out while the track changes, retryable on failure.
@MainActor
struct ItineraryEditorStoreElevationTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.120)
    private let c = Coordinate(latitude: 45.902, longitude: 6.121)

    private func makeStore(previewer: FakeItineraryMetricsPreviewer) -> ItineraryEditorStore {
        ItineraryEditorStore(editor: ItineraryEditor(
            sport: .run,
            router: FakeItineraryRouter(),
            metricsPreviewer: previewer,
            pauseDelay: .seconds(60)
        ))
    }

    private func trace(_ store: ItineraryEditorStore, through points: [Coordinate]) async {
        for point in points {
            store.tap(at: point)
            await store.editor.settle()
        }
    }

    @Test func theGainMeasuredByIGNIsShownAsIsAndCredited() async {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 41.6, source: .ign))
        let store = makeStore(previewer: previewer)
        #expect(store.elevationText == "—")
        #expect(store.elevationSourceText == nil)

        await trace(store, through: [a, b])

        #expect(store.elevationText == "42 m")
        #expect(store.elevationSourceText == "Altitudes : IGN")
        #expect(!store.isElevationStale)
        #expect(!store.isElevationUnavailable)
    }

    @Test(arguments: [
        (ElevationSource.mixed, "Altitudes : IGN, Open-Meteo / Copernicus"),
        (ElevationSource.openMeteo, "Altitudes : Open-Meteo / Copernicus"),
    ])
    func aGainWithOpenMeteoAltitudesIsApproximate(source: ElevationSource, credit: String) async {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 42, source: source))
        let store = makeStore(previewer: previewer)

        await trace(store, through: [a, b])

        #expect(store.elevationText == "≈ 42 m")
        #expect(store.elevationSourceText == credit)
    }

    @Test func theGainIsGreyedOutWhileAWaypointIsDragged() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 42))
        let store = makeStore(previewer: previewer)
        await trace(store, through: [a, b])
        let finish = try #require(store.markers.last)

        store.beginDrag(finish.id, at: .zero)
        store.drag(to: c, at: CGPoint(x: 40, y: 40))

        #expect(store.isElevationStale)
        #expect(store.elevationText == "42 m")

        store.endDrag(at: c, point: CGPoint(x: 40, y: 40))
        await store.editor.settle()

        #expect(!store.isElevationStale)
    }

    @Test func anUnavailableGainOffersARetry() async {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.fail(with: .unavailable)
        let store = makeStore(previewer: previewer)
        await trace(store, through: [a, b])

        #expect(store.isElevationUnavailable)
        #expect(store.elevationSourceText == nil)

        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 42))
        store.retryElevation()
        await store.editor.settle()

        #expect(!store.isElevationUnavailable)
        #expect(store.elevationText == "42 m")
    }
}
