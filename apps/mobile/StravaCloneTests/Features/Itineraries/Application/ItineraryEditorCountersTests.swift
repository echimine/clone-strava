import Foundation
import Testing
@testable import StravaClone

/// Session counters of the editor (issue #20): what the athlete did and what the router
/// answered, sent once when the editor closes instead of one event per gesture.
@MainActor
struct ItineraryEditorCountersTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let d = Coordinate(latitude: 45.903, longitude: 6.122)

    private func makeEditor(router: FakeItineraryRouter) -> ItineraryEditor {
        ItineraryEditor(
            sport: .run,
            router: router,
            pauseDelay: .seconds(60),
            // The backoff after a `429` never ends during a test.
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
    }

    private func add(_ points: [Coordinate], to editor: ItineraryEditor) async {
        for point in points {
            editor.addWaypoint(at: point)
            await editor.settle()
        }
    }

    @Test func gesturesAreCounted() async {
        let editor = makeEditor(router: FakeItineraryRouter())
        await add([a, b, c], to: editor)

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: d)
        editor.endDrag()
        await editor.settle()
        // Resting on a Waypoint without moving it is not a move.
        editor.beginDrag(editor.draft.waypoints[0].id)
        editor.endDrag()
        editor.beginInsertion(intoLeg: editor.draft.legs[0].id, at: Coordinate(latitude: 45.9005, longitude: 6.1205))
        editor.endDrag()
        await editor.settle()
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)
        editor.setMode(.follow, ofLeg: editor.draft.legs[0].id)
        await editor.settle()
        editor.undo()
        editor.undo()
        editor.redo()
        await editor.settle()

        let counters = editor.counters
        #expect(counters.waypointsAdded == 3)
        #expect(counters.waypointsMoved == 1)
        #expect(counters.waypointsInserted == 1)
        #expect(counters.legsSwitchedToStraight == 1)
        #expect(counters.undos == 2)
        #expect(counters.redos == 1)
    }

    @Test func aRefusedOrEmptyGestureIsNotCounted() async {
        let editor = makeEditor(router: FakeItineraryRouter())

        editor.undo()
        editor.redo()

        #expect(editor.counters == ItineraryEditorCounters())
    }

    @Test func routerRequestsAndTheirFailuresAreCountedByKind() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await add([a, b], to: editor)

        await router.fail(with: .noPath)
        await add([c], to: editor)
        await router.fail(with: .temporary)
        await add([d], to: editor)
        await router.fail(with: .rateLimited)
        editor.retryPendingLegs()
        await editor.settle()

        let counters = editor.counters
        #expect(await router.calls.count == 4)
        #expect(counters.directionsRequests == 4)
        #expect(counters.noPathResponses == 1)
        #expect(counters.networkFailures == 1)
        #expect(counters.rateLimitedResponses == 1)
    }
}
