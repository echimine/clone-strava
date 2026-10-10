import Foundation
import Testing
@testable import StravaClone

/// Undo / redo (ADR-030 §2): one entry per gesture (a full drag, an insertion, a removal,
/// a mode change, an added Waypoint); router answers are not entries of their own.
@MainActor
struct ItineraryEditorUndoTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let x = Coordinate(latitude: 45.904_2, longitude: 6.123_8)
    private let y = Coordinate(latitude: 45.905_1, longitude: 6.118_9)

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

    @Test func aFullDragIsOneEntryAndUndoThenRedoRestoresTheExactState() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b, c], router: router, pauseDelay: .milliseconds(10))
        let beforeDrag = editor.draft

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)
        await router.waitForCalls(3)
        await editor.settle()
        editor.drag(to: y)
        editor.endDrag()
        await editor.settle()
        let afterDrag = editor.draft
        let calls = await router.calls.count

        editor.undo()
        #expect(editor.draft == beforeDrag)
        editor.undo()
        #expect(editor.draft.waypoints.count == 2)

        editor.redo()
        editor.redo()
        #expect(editor.draft == afterDrag)
        #expect(!editor.canRedo)
        await editor.settle()
        #expect(await router.calls.count == calls)
    }

    @Test func eachGestureIsOneEntry() async {
        let editor = await makeEditor(through: [a, b, c])
        var states = [editor.draft]

        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)
        states.append(editor.draft)
        editor.beginInsertion(intoLeg: editor.draft.legs[1].id, at: x)
        editor.drag(to: y)
        editor.endDrag()
        await editor.settle()
        states.append(editor.draft)
        editor.removeWaypoint(editor.draft.waypoints[1].id)
        await editor.settle()
        states.append(editor.draft)

        for expected in states.dropLast().reversed() {
            editor.undo()
            #expect(editor.draft == expected)
        }
        for expected in states.dropFirst() {
            editor.redo()
            #expect(editor.draft == expected)
        }
    }

    @Test func addingWaypointsCanBeUndoneDownToAnEmptyMap() async {
        let editor = await makeEditor(through: [a, b])
        #expect(editor.canUndo)
        #expect(!editor.canRedo)

        editor.undo()
        #expect(editor.draft.waypoints.map(\.coordinate) == [a])
        editor.undo()
        #expect(editor.draft.waypoints.isEmpty)
        #expect(!editor.canUndo)
        #expect(editor.canRedo)
    }

    @Test func aNewGestureClearsWhatCouldBeRedone() async {
        let editor = await makeEditor(through: [a, b, c])

        editor.undo()
        #expect(editor.canRedo)
        editor.setMode(.straight, ofLeg: editor.draft.legs[0].id)

        #expect(!editor.canRedo)
    }

    @Test func aGestureThatChangesNothingIsNotAnEntry() async {
        let editor = await makeEditor(through: [a, b])
        editor.undo()
        editor.redo()

        editor.setMode(.follow, ofLeg: editor.draft.legs[0].id)
        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.endDrag()
        editor.undo()

        #expect(editor.draft.waypoints.map(\.coordinate) == [a])
    }

    @Test func undoAndRedoWaitForTheEndOfADrag() async {
        let editor = await makeEditor(through: [a, b])
        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)

        #expect(!editor.canUndo)
        editor.undo()
        #expect(editor.draft.waypoints[1].coordinate == x)

        editor.endDrag()
        await editor.settle()
        #expect(editor.canUndo)
    }

    @Test func redoingALegThatWasStillComputingRequestsItAgain() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(through: [a, b], router: router)
        let beforeDrag = editor.draft
        await router.hold()

        editor.beginDrag(editor.draft.waypoints[1].id)
        editor.drag(to: x)
        editor.endDrag()
        await router.waitForCalls(2)
        editor.undo()
        await router.release()
        await editor.settle()

        // The answer was for the undone drag: ignored.
        #expect(editor.draft == beforeDrag)

        editor.redo()
        await editor.settle()
        #expect(await router.calls.dropFirst(1).map(\.waypoints) == [[a, x], [a, x]])
        #expect(editor.draft.waypoints[1].coordinate == FakeItineraryRouter.snap(x))
        #expect(editor.draft.legs.map(\.state) == [.computed])
    }
}
