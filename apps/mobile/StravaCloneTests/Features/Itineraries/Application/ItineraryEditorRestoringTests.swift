import Foundation
import Testing
@testable import StravaClone

/// The editor reopened on a saved Itinerary (ADR-030 §5, §8): no Directions request, the
/// gain measured once, and editing goes on as for a new Itinerary.
@MainActor
struct ItineraryEditorRestoringTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let corner = Coordinate(latitude: 45.900, longitude: 6.121)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.910, longitude: 6.121)

    /// Waypoint and Leg ids are generated: one draft per test, compared with itself.
    private let draft: ItineraryDraft

    init() {
        draft = ItineraryDraft(restoring: SavedItinerary(
            id: .fixture(7),
            name: "Tour du lac",
            sport: .hike,
            waypoints: [a, b, c],
            legs: [.follow(EncodedPolyline(encoding: [a, corner, b], precision: 6)), .straight]
        ))!
    }

    @Test func reopeningSendsNoDirectionsRequest() async {
        let router = FakeItineraryRouter()

        let editor = ItineraryEditor(restoring: draft, router: router)
        await editor.settle()

        #expect(await router.calls.isEmpty)
        #expect(editor.draft == draft)
        #expect(!editor.canUndo)
    }

    @Test func theGainOfTheReopenedTrackIsMeasuredOnce() async {
        let previewer = FakeItineraryMetricsPreviewer()

        let editor = ItineraryEditor(restoring: draft, router: FakeItineraryRouter(), metricsPreviewer: previewer)
        await editor.settle()

        #expect(await previewer.requests == [draft.geometry])
        #expect(editor.elevation.status == .measured)
    }

    /// Moving a Waypoint requests only its Legs, like any edit.
    @Test func aGestureRoutesOnlyTheLegsItChanges() async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(restoring: draft, router: router)
        let finish = editor.draft.waypoints[2].id

        editor.beginDrag(finish)
        editor.drag(to: Coordinate(latitude: 45.911, longitude: 6.122))
        editor.endDrag()
        await editor.settle()

        // The Leg to the finish is straight: nothing to route.
        #expect(await router.calls.isEmpty)
        #expect(editor.canUndo)

        editor.setMode(.follow, ofLeg: editor.draft.legs[1].id)
        await editor.settle()
        #expect(await router.calls.map(\.waypoints) == [[b, Coordinate(latitude: 45.911, longitude: 6.122)]])
    }
}
