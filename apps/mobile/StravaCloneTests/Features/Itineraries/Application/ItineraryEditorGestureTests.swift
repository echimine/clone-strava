import Foundation
import Testing
@testable import StravaClone

/// Editing gestures (ADR-030 §2): Leg mode, removal, drag and insertion, with a fake
/// router at the Domain protocol. Waypoints sit on the fake network's 0.001° grid, so a
/// routed Leg keeps them in place and turns once at `(start.lat, end.lon)`.
@MainActor
struct ItineraryEditorGestureTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let d = Coordinate(latitude: 45.903, longitude: 6.122)

    /// An editor whose Itinerary goes through `points`, every Leg routed.
    private func makeEditor(
        through points: [Coordinate],
        router: FakeItineraryRouter = FakeItineraryRouter(),
        pauseDelay: Duration = .seconds(60)
    ) async -> ItineraryEditor {
        let editor = ItineraryEditor(sport: .run, router: router, pauseDelay: pauseDelay)
        for point in points {
            editor.addWaypoint(at: point)
            await editor.settle()
        }
        return editor
    }

    private func corner(_ start: Coordinate, _ end: Coordinate) -> Coordinate {
        Coordinate(latitude: start.latitude, longitude: end.longitude)
    }

    // MARK: Leg mode

    @Test func switchingALegToStraightThenBackToFollowRequestsOnlyThatLeg() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c, d], router: router)
        let middle = editor.draft.legs[1].id

        editor.setMode(.straight, ofLeg: middle)
        await editor.settle()

        #expect(editor.draft.legs.map(\.mode) == [.follow, .straight, .follow])
        #expect(editor.draft.geometry(ofLegAt: 1) == [b, c])
        #expect(await router.calls.count == 3)

        editor.setMode(.follow, ofLeg: middle)
        await editor.settle()

        #expect(await router.calls.dropFirst(3).map(\.waypoints) == [[b, c]])
        #expect(editor.draft.legs.map(\.mode) == [.follow, .follow, .follow])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed, .computed])
        #expect(editor.draft.geometry(ofLegAt: 1) == [b, corner(b, c), c])
    }

    // MARK: Removal

    @Test func removingAMiddleWaypointJoinsItsNeighboursWithOneNewLeg() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c, d], router: router)
        let lastLeg = editor.draft.legs[2]

        editor.removeWaypoint(editor.draft.waypoints[1].id)
        await editor.settle()

        #expect(editor.draft.waypoints.map(\.coordinate) == [a, c, d])
        #expect(editor.draft.legs.count == 2)
        #expect(await router.calls.dropFirst(3).map(\.waypoints) == [[a, c]])
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, corner(a, c), c])
        #expect(editor.draft.legs[1] == lastLeg)
    }

    @Test func removingTheStartMakesTheNextWaypointTheStart() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        let remainingLeg = editor.draft.legs[1]

        editor.removeWaypoint(editor.draft.waypoints[0].id)
        await editor.settle()

        #expect(editor.draft.waypoints.map(\.coordinate) == [b, c])
        #expect(editor.draft.legs == [remainingLeg])
        #expect(await router.calls.count == 2)
    }

    @Test func removingTheFinishMakesThePreviousWaypointTheFinish() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        let remainingLeg = editor.draft.legs[0]

        editor.removeWaypoint(editor.draft.waypoints[2].id)
        await editor.settle()

        #expect(editor.draft.waypoints.map(\.coordinate) == [a, b])
        #expect(editor.draft.legs == [remainingLeg])
        #expect(await router.calls.count == 2)
    }

    @Test func removingAWaypointOfTheOnlyLegLeavesTheOtherOneAsTheStart() async {
        let editor = await makeEditor(through: [a, b])

        editor.removeWaypoint(editor.draft.waypoints[0].id)
        #expect(editor.draft.waypoints.map(\.coordinate) == [b])
        #expect(editor.draft.legs.isEmpty)
        #expect(editor.draft.distance == .zero)

        editor.removeWaypoint(editor.draft.waypoints[0].id)
        #expect(editor.draft.waypoints.isEmpty)
    }

    @Test func removingAWaypointBetweenTwoStraightLegsJoinsItsNeighboursInAStraightLine() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)
        editor.setMode(.straight, ofLeg: editor.draft.legs[1].id)

        editor.removeWaypoint(editor.draft.waypoints[1].id)
        await editor.settle()

        #expect(editor.draft.legs.map(\.mode) == [.straight])
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, c])
        #expect(await router.calls.count == 2)
    }

    @Test func removingAWaypointBesideAFollowLegJoinsItsNeighboursAlongTheNetwork() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)

        editor.removeWaypoint(editor.draft.waypoints[1].id)
        await editor.settle()

        #expect(editor.draft.legs.map(\.mode) == [.follow])
        #expect(await router.calls.dropFirst(2).map(\.waypoints) == [[a, c]])
    }

    // MARK: Drag

    // Off the grid, so the fake network visibly snaps them.
    private let x = Coordinate(latitude: 45.904_2, longitude: 6.123_8)
    private let y = Coordinate(latitude: 45.905_1, longitude: 6.118_9)

    @Test func whileTheFingerMovesTheNeighbourLegsAreStraightAndNothingIsRequested() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        let dragged = editor.draft.waypoints[1].id

        editor.beginDrag(dragged)
        editor.drag(to: x)
        editor.drag(to: y)

        #expect(editor.draggedWaypointID == dragged)
        #expect(editor.draft.waypoints[1].coordinate == y)
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, y])
        #expect(editor.draft.geometry(ofLegAt: 1) == [y, c])
        #expect(editor.draft.legs.map(\.state) == [.computing, .computing])
        #expect(await router.calls.count == 2)
        editor.endDrag()
        await editor.settle()
    }

    @Test func releasingADraggedWaypointRequestsItsTwoLegsInOneCall() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c, d], router: router)
        let untouched = editor.draft.legs[2]

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: y)
        editor.drag(to: x)
        editor.endDrag()
        await editor.settle()

        #expect(await router.calls.dropFirst(3).map(\.waypoints) == [[a, x, c]])
        let snapped = FakeItineraryRouter.snap(x)
        #expect(editor.draggedWaypointID == nil)
        #expect(editor.draft.waypoints.map(\.coordinate) == [a, snapped, c, d])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed, .computed])
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, corner(a, snapped), snapped])
        #expect(editor.draft.legs[2] == untouched)
    }

    @Test func releasingTheFinishRequestsOnlyItsLeg() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)

        editor.beginDrag(editor.draft.waypoints[2].id)
        editor.drag(to: x)
        editor.endDrag()
        await editor.settle()

        #expect(await router.calls.dropFirst(2).map(\.waypoints) == [[b, x]])
    }

    @Test func aStraightNeighbourLegIsNotRequested() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)
        editor.endDrag()
        await editor.settle()

        let snapped = FakeItineraryRouter.snap(x)
        #expect(await router.calls.dropFirst(2).map(\.waypoints) == [[x, c]])
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, snapped])
        #expect(editor.draft.legs.map(\.mode) == [.straight, .follow])
    }

    @Test func touchingAWaypointWithoutMovingItRequestsNothing() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        let before = editor.draft

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.endDrag()
        await editor.settle()

        #expect(editor.draft == before)
        #expect(await router.calls.count == 2)
    }

    @Test func aPausePreviewsTheRoutedLegsWhileTheMarkerStaysUnderTheFinger() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router, pauseDelay: .milliseconds(10))

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)
        await router.waitForCalls(3)
        await editor.settle()

        let snapped = FakeItineraryRouter.snap(x)
        #expect(await router.calls.last?.waypoints == [a, x, c])
        #expect(editor.draft.waypoints[1].coordinate == x)
        #expect(editor.displayedDraft.geometry(ofLegAt: 0) == [a, corner(a, snapped), snapped])
        #expect(editor.displayedDraft.waypoints[1].coordinate == snapped)

        // Released where it rested: the pause answer is applied, nothing more is requested.
        editor.endDrag()
        await editor.settle()
        #expect(await router.calls.count == 3)
        #expect(editor.draft.waypoints[1].coordinate == snapped)
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed])
        #expect(editor.displayedDraft == editor.draft)
    }

    @Test func movingAgainAfterAPauseDropsItsAnswerAndRequestsOnRelease() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router, pauseDelay: .milliseconds(10))
        await router.hold()

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)
        await router.waitForCalls(3)
        editor.drag(to: y)
        #expect(editor.displayedDraft == editor.draft)
        editor.endDrag()
        await router.waitForCalls(4)
        await router.release()
        await editor.settle()

        #expect(await router.calls.dropFirst(2).map(\.waypoints) == [[a, x, c], [a, y, c]])
        #expect(editor.draft.waypoints[1].coordinate == FakeItineraryRouter.snap(y))
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed])
    }

    // MARK: Insertion

    private let middleOfFirstLeg = Coordinate(latitude: 45.900_4, longitude: 6.121_1)

    @Test func pullingALegInsertsAWaypointThatFollowsTheFinger() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router)
        let untouched = editor.draft.legs[1]

        editor.beginInsertion(intoLeg: editor.draft.legs[0].id, at: middleOfFirstLeg)
        #expect(editor.draft.waypoints.map(\.coordinate) == [a, middleOfFirstLeg, b, c])
        #expect(editor.draggedWaypointID == editor.draft.waypoints[1].id)
        editor.drag(to: x)
        editor.endDrag()
        await editor.settle()

        let snapped = FakeItineraryRouter.snap(x)
        #expect(await router.calls.dropFirst(2).map(\.waypoints) == [[a, x, b]])
        #expect(editor.draft.waypoints.map(\.coordinate) == [a, snapped, b, c])
        #expect(editor.draft.legs.count == 3)
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed, .computed])
        #expect(editor.draft.geometry(ofLegAt: 1) == [snapped, corner(snapped, b), b])
        #expect(editor.draft.legs[2] == untouched)
    }

    @Test func releasingAPulledLegWithoutMovingInsertsTheWaypointWhereItWasPulled() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b], router: router)

        editor.beginInsertion(intoLeg: editor.draft.legs[0].id, at: middleOfFirstLeg)
        editor.endDrag()
        await editor.settle()

        #expect(await router.calls.dropFirst(1).map(\.waypoints) == [[a, middleOfFirstLeg, b]])
        #expect(editor.draft.waypoints.map(\.coordinate) == [a, FakeItineraryRouter.snap(middleOfFirstLeg), b])
    }

    @Test func pullingAStraightLegSplitsItIntoTwoStraightLegs() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b], router: router)
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)

        editor.beginInsertion(intoLeg: editor.draft.legs[0].id, at: middleOfFirstLeg)
        editor.drag(to: x)
        editor.endDrag()
        await editor.settle()

        #expect(editor.draft.waypoints.map(\.coordinate) == [a, x, b])
        #expect(editor.draft.legs.map(\.mode) == [.straight, .straight])
        #expect(await router.calls.count == 1)
    }
}
