import Foundation
import Testing
@testable import StravaClone

/// Changing the sport while editing (ADR-030 §2): across categories the `follow` Legs are
/// requested again in parallel batches, editing goes on meanwhile, and the change is one
/// undo entry. Waypoints sit on the fake network's 0.001° grid, so routing keeps them in place.
@MainActor
struct ItineraryEditorSportChangeTests {
    /// Grid node `index` steps north of the first one, exact as the fake network snaps it.
    private func point(_ index: Int) -> Coordinate {
        Coordinate(latitude: Double(45_900 + index) / 1_000, longitude: 6.12)
    }

    /// An editor through `count` Waypoints on foot, every Leg routed.
    private func makeEditor(router: FakeItineraryRouter, waypoints count: Int) async -> ItineraryEditor {
        let editor = ItineraryEditor(sport: .run, router: router, pauseDelay: .seconds(60))
        for index in 0 ..< count {
            editor.addWaypoint(at: point(index))
            await editor.settle()
        }
        return editor
    }

    @Test func aSportOfTheSameCategoryRequestsNothing() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 3)
        let legs = editor.draft.legs

        editor.changeSport(to: .walk)
        await editor.settle()

        #expect(editor.draft.sport == .walk)
        #expect(editor.draft.legs == legs)
        #expect(await router.calls.count == 2)
    }

    @Test func anotherCategoryRequestsTheBatchesInParallel() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        await router.hold()

        editor.changeSport(to: .ride)
        await router.waitForCalls(29 + 2)

        #expect(editor.draft.sport == .ride)
        #expect(editor.draft.legs.allSatisfy { $0.state == .computing })
        let batches = await router.calls.dropFirst(29)
        #expect(batches.map(\.waypoints) == [(0 ... 24).map(point), (24 ... 29).map(point)])
        #expect(batches.allSatisfy { $0.profile == .cycling })

        await router.release()
        await editor.settle()

        #expect(editor.draft.legs.allSatisfy { $0.state == .computed })
        #expect(editor.draft.waypoints.map(\.coordinate) == (0 ... 29).map(point))
        #expect(await router.calls.count == 29 + 2)
    }

    @Test func straightLegsAreNeverRequested() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 10)
        editor.setMode(.straight, ofLeg: editor.draft.legs[2].id)
        editor.setMode(.straight, ofLeg: editor.draft.legs[3].id)
        let straight = editor.draft.legs[2 ... 3]

        editor.changeSport(to: .ride)
        await editor.settle()

        #expect(await router.calls.dropFirst(9).map(\.waypoints) == [(0 ... 2).map(point), (4 ... 9).map(point)])
        #expect(editor.draft.legs[2 ... 3] == straight)
        #expect(editor.draft.metricsRequest != nil)
    }

    @Test func aBatchWithNoPathIsRequestedLegByLeg() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        await router.answer { waypoints in
            guard waypoints.count == 2 else { throw RoutingError.noPath }
            return FakeItineraryRouter.gridPath(waypoints)
        }

        editor.changeSport(to: .ride)
        await editor.settle()

        let retries = await router.calls.dropFirst(29 + 2)
        #expect(retries.count == 29)
        #expect(Set(retries.map(\.waypoints)) == Set((0 ..< 29).map { [point($0), point($0 + 1)] }))
        #expect(retries.allSatisfy { $0.profile == .cycling })
        #expect(editor.draft.legs.allSatisfy { $0.mode == .follow && $0.state == .computed })
        #expect(editor.notice == nil)
    }

    // MARK: Editing meanwhile

    /// Every `follow` Leg has its path for the new sport, nothing waits any more.
    private func expectEveryFollowLegRouted(_ editor: ItineraryEditor, router: FakeItineraryRouter, after setupCalls: Int) async {
        #expect(editor.draft.legs.filter { $0.mode == .follow }.allSatisfy { $0.state == .computed })
        #expect(editor.draft.metricsRequest != nil)
        #expect(await router.calls.dropFirst(setupCalls).allSatisfy { $0.profile == .cycling })
    }

    @Test func aLegTurnedStraightDuringTheRecomputationDoesNotStrandItsBatch() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        await router.hold()

        editor.changeSport(to: .ride)
        await router.waitForCalls(29 + 2)
        editor.setMode(.straight, ofLeg: editor.draft.legs[5].id)
        await router.release()
        await editor.settle()

        #expect(editor.draft.legs[5].mode == .straight)
        await expectEveryFollowLegRouted(editor, router: router, after: 29)
        let straight = [point(5), point(6)]
        #expect(await !router.calls.dropFirst(29 + 2).contains { $0.waypoints == straight })
    }

    @Test func aWaypointRemovedDuringTheRecomputationDoesNotStrandItsBatch() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        await router.hold()

        editor.changeSport(to: .ride)
        await router.waitForCalls(29 + 2)
        editor.removeWaypoint(editor.draft.waypoints[10].id)
        await router.release()
        await editor.settle()

        #expect(editor.draft.waypoints.count == 29)
        await expectEveryFollowLegRouted(editor, router: router, after: 29)
    }

    @Test func waypointsCanBeAddedAndDraggedDuringTheRecomputation() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        await router.hold()

        editor.changeSport(to: .ride)
        await router.waitForCalls(29 + 2)
        editor.addWaypoint(at: point(30))
        editor.beginDrag(editor.draft.waypoints[3].id)
        editor.drag(to: Coordinate(latitude: 45.903, longitude: 6.121))
        editor.endDrag()
        await router.release()
        await editor.settle()

        #expect(editor.draft.waypoints.count == 31)
        #expect(editor.draft.waypoints[3].coordinate == Coordinate(latitude: 45.903, longitude: 6.121))
        await expectEveryFollowLegRouted(editor, router: router, after: 29)
    }

    // MARK: Undo

    @Test func undoRestoresTheSportAndTheLegsOfBeforeAtOnce() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        let before = editor.draft

        editor.changeSport(to: .ride)
        await editor.settle()
        let after = editor.draft

        editor.undo()
        #expect(editor.draft == before)
        editor.redo()
        #expect(editor.draft == after)
        await editor.settle()
        #expect(await router.calls.count == 29 + 2)
    }

    @Test func undoDuringTheRecomputationDropsItsAnswers() async {
        let router = FakeItineraryRouter()
        let editor = await makeEditor(router: router, waypoints: 30)
        let before = editor.draft
        await router.hold()

        editor.changeSport(to: .ride)
        await router.waitForCalls(29 + 2)
        editor.undo()
        await router.release()
        await editor.settle()

        #expect(editor.draft == before)
        #expect(editor.draft.sport == .run)
        #expect(await router.calls.count == 29 + 2)
    }
}
