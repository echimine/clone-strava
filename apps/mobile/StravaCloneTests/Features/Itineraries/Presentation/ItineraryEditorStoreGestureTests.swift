import Foundation
import Testing
@testable import StravaClone

/// Screen side of the editing gestures: bubbles, drag handling, insertion handles, undo.
@MainActor
struct ItineraryEditorStoreGestureTests {
    // Points on the fake network's grid; x and y are off it, so they get snapped.
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.902, longitude: 6.120)
    private let c = Coordinate(latitude: 45.902, longitude: 6.122)
    private let x = Coordinate(latitude: 45.904_2, longitude: 6.123_8)
    private let y = Coordinate(latitude: 45.905_1, longitude: 6.118_9)

    private func makeStore(
        through points: [Coordinate],
        router: FakeItineraryRouter = FakeItineraryRouter(),
        pauseDelay: Duration = .seconds(60)
    ) async -> ItineraryEditorStore {
        let store = ItineraryEditorStore(editor: ItineraryEditor(sport: .run, router: router, pauseDelay: pauseDelay))
        for point in points {
            store.tap(at: point)
            await store.editor.settle()
        }
        return store
    }

    @Test func tappingAWaypointOpensABubbleToRemoveIt() async {
        let store = await makeStore(through: [a, b, c])
        let middle = store.markers[1].id

        store.tapWaypoint(middle)
        #expect(store.selection == .waypoint(middle))

        store.removeSelectedWaypoint()
        await store.editor.settle()
        #expect(store.markers.map(\.coordinate) == [a, c])
        #expect(store.selection == nil)
    }

    @Test func tappingALegOpensABubbleToSwitchItsMode() async {
        let store = await makeStore(through: [a, b, c])
        let first = store.lines[0].id

        store.tapLeg(first, at: a)
        #expect(store.selection == .leg(first, at: a))
        #expect(store.selectedLegMode == .follow)

        store.setSelectedLegMode(.straight)
        #expect(store.lines[0].coordinates == [a, b])
        #expect(store.selection == nil)
    }

    @Test func tappingTheMapWhileABubbleIsOpenOnlyClosesIt() async {
        let store = await makeStore(through: [a, b])
        store.tapWaypoint(store.markers[0].id)

        store.tap(at: c)

        #expect(store.selection == nil)
        #expect(store.markers.count == 2)
    }

    @Test func fingerMovesUnderEightPointsAreIgnored() async {
        let store = await makeStore(through: [a, b])
        let finish = store.markers[1].id

        store.beginDrag(finish, at: CGPoint(x: 100, y: 100))
        store.drag(to: x, at: CGPoint(x: 104, y: 105))
        #expect(store.markers[1].coordinate == b)

        store.drag(to: y, at: CGPoint(x: 100, y: 112))
        #expect(store.markers[1].coordinate == y)
        store.endDrag(at: x, point: CGPoint(x: 103, y: 110))
        await store.editor.settle()
        #expect(store.markers[1].coordinate == FakeItineraryRouter.snap(y))
    }

    @Test func whileMovingTheDistanceIsStaleThenAPauseShowsThePathToTheSnappedPoint() async {
        let router = FakeItineraryRouter()
        let store = await makeStore(through: [a, b], router: router, pauseDelay: .milliseconds(10))
        let finish = store.markers[1].id

        store.beginDrag(finish, at: CGPoint(x: 100, y: 100))
        store.drag(to: x, at: CGPoint(x: 150, y: 100))
        #expect(store.isDistanceStale)
        #expect(store.lines.map(\.isProvisional) == [true])
        #expect(store.snapConnector == nil)

        await router.waitForCalls(2)
        await store.editor.settle()
        let snapped = FakeItineraryRouter.snap(x)
        #expect(!store.isDistanceStale)
        #expect(store.lines.map(\.isProvisional) == [false])
        #expect(store.lines[0].coordinates.last == snapped)
        #expect(store.markers[1].coordinate == x)
        #expect(store.snapConnector == [snapped, x])

        store.endDrag(at: x, point: CGPoint(x: 150, y: 100))
        #expect(store.markers[1].coordinate == snapped)
        #expect(store.snapConnector == nil)
    }

    @Test func eachLegHasAnInsertionHandleInItsMiddleHiddenDuringADrag() async throws {
        let store = await makeStore(through: [a, b])

        let handle = try #require(store.insertionHandles.first)
        #expect(store.insertionHandles.count == 1)
        #expect(handle.id == store.lines[0].id)
        #expect(abs(handle.coordinate.latitude - 45.901) < 1e-9)
        #expect(abs(handle.coordinate.longitude - 6.120) < 1e-9)

        #expect(store.showsInsertionHandles)

        // The pulled handle stays mounted under the finger, so its gesture goes on.
        store.beginInsertion(intoLeg: handle.id, at: handle.coordinate, point: CGPoint(x: 10, y: 10))
        #expect(!store.showsInsertionHandles)
        #expect(store.insertionHandles.map(\.id).contains(handle.id))
        #expect(store.markers.count == 3)
        store.endDrag(at: handle.coordinate, point: CGPoint(x: 10, y: 10))
        await store.editor.settle()
        #expect(store.showsInsertionHandles)
        #expect(store.insertionHandles.count == 2)
    }

    @Test func undoAndRedoFollowTheGestures() async {
        let store = await makeStore(through: [a])
        #expect(store.canUndo)
        #expect(!store.canRedo)
        store.tapWaypoint(store.markers[0].id)

        store.undo()
        #expect(store.markers.isEmpty)
        #expect(store.selection == nil)
        #expect(store.canRedo)

        store.redo()
        #expect(store.markers.map(\.coordinate) == [a])
    }
}
