import Foundation
import Testing
@testable import StravaClone

/// Editor model driven by taps (ADR-030 §2), with a fake router at the Domain protocol.
/// Taps are placed off the fake network's 0.001° grid so snapping is visible.
@MainActor
struct ItineraryEditorTests {
    private let start = Coordinate(latitude: 45.900_2, longitude: 6.120_3)
    private let second = Coordinate(latitude: 45.902_2, longitude: 6.121_8)
    private let third = Coordinate(latitude: 45.904_1, longitude: 6.123_2)

    private func snapped(_ coordinate: Coordinate) -> Coordinate {
        FakeItineraryRouter.snap(coordinate)
    }

    @Test func firstTapPlacesTheStartWithoutRouting() async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: .run, router: router)

        editor.addWaypoint(at: start)
        await editor.settle()

        #expect(editor.draft.waypoints.map(\.coordinate) == [start])
        #expect(editor.draft.legs.isEmpty)
        #expect(editor.draft.distance == .zero)
        #expect(await router.calls.isEmpty)
    }

    @Test func nextTapAddsALegThatFollowsTheNetworkToTheSnappedWaypoint() async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: .run, router: router)

        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()

        #expect(await router.calls == [.init(waypoints: [start, second], profile: .walking)])
        #expect(editor.draft.waypoints.map(\.coordinate) == [snapped(start), snapped(second)])
        let leg = editor.draft.legs.first
        #expect(editor.draft.legs.count == 1)
        #expect(leg?.mode == .follow)
        #expect(leg?.state == .computed)
        #expect(editor.draft.geometry(ofLegAt: 0) == [
            Coordinate(latitude: 45.900, longitude: 6.120),
            Coordinate(latitude: 45.900, longitude: 6.122),
            Coordinate(latitude: 45.902, longitude: 6.122),
        ])
        #expect(editor.notice == nil)
    }

    @Test func eachTapAppendsAWaypointAndTheLastOneIsTheFinish() async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: .hike, router: router)

        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()
        editor.addWaypoint(at: third)
        await editor.settle()

        // The new Leg starts from the position the previous Leg snapped.
        #expect(await router.calls.map(\.waypoints) == [[start, second], [snapped(second), third]])
        #expect(editor.draft.waypoints.map(\.coordinate) == [snapped(start), snapped(second), snapped(third)])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed])
        #expect(editor.draft.waypoints.last?.coordinate == snapped(third))
    }

    @Test(arguments: [
        (ItinerarySport.run, RoutingProfile.walking),
        (.walk, .walking),
        (.hike, .walking),
        (.ride, .cycling),
    ])
    func profileComesFromTheSportCategory(sport: ItinerarySport, profile: RoutingProfile) async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: sport, router: router)

        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()

        #expect(await router.calls.map(\.profile) == [profile])
    }

    @Test func swimmingIsNotOffered() {
        #expect(!ItinerarySport.allCases.map(\.sportType).contains(.swim))
        #expect(ItinerarySport.allCases.count == 4)
    }

    @Test func withoutAPathTheLegFallsBackToAStraightLineAndTheWaypointStaysWherePlaced() async {
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: .run, router: router)
        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()

        await router.fail(with: .noPath)
        editor.addWaypoint(at: third)
        await editor.settle()

        let leg = editor.draft.legs[1]
        #expect(leg.mode == .straight)
        #expect(leg.state == .computed)
        #expect(editor.draft.waypoints[2].coordinate == third)
        #expect(editor.draft.geometry(ofLegAt: 1) == [snapped(second), third])
        #expect(editor.notice == .noPath)
    }

    @Test(arguments: [
        (RoutingError.temporary, ItineraryEditor.Notice.routingUnavailable),
        (.rateLimited, .routingSaturated),
    ])
    func aTemporaryFailureLeavesTheLegFollowingButPending(error: RoutingError, notice: ItineraryEditor.Notice) async {
        let router = FakeItineraryRouter()
        await router.fail(with: error)
        let editor = ItineraryEditor(sport: .ride, router: router)

        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()

        #expect(editor.draft.legs.map(\.mode) == [.follow])
        #expect(editor.draft.legs.map(\.state) == [.pending])
        #expect(editor.draft.waypoints.map(\.coordinate) == [start, second])
        #expect(editor.notice == notice)
    }

    @Test func theLegIsComputingAsAStraightLineUntilTheRouterAnswers() async {
        let router = FakeItineraryRouter()
        await router.hold()
        let editor = ItineraryEditor(sport: .run, router: router)

        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await router.waitForCalls(1)

        #expect(editor.draft.legs.map(\.state) == [.computing])
        #expect(editor.draft.geometry(ofLegAt: 0) == [start, second])

        await router.release()
        await editor.settle()
        #expect(editor.draft.legs.map(\.state) == [.computed])
    }

    @Test func distanceIsUpdatedOnEachAddition() async {
        let router = FakeItineraryRouter()
        await router.hold()
        let editor = ItineraryEditor(sport: .run, router: router)
        // Along a meridian, 0.001° of latitude is 111.195 m.
        let a = Coordinate(latitude: 45.900, longitude: 6.120)
        let b = Coordinate(latitude: 45.901, longitude: 6.120)
        let c = Coordinate(latitude: 45.903, longitude: 6.120)

        editor.addWaypoint(at: a)
        #expect(editor.draft.distance == .zero)

        editor.addWaypoint(at: b)
        #expect(abs(editor.draft.distance.meters - 111.195) < 0.01)

        editor.addWaypoint(at: c)
        #expect(abs(editor.draft.distance.meters - 333.585) < 0.01)

        await router.release()
        await editor.settle()
    }

    @Test func distanceFollowsTheRoutedGeometry() async {
        let router = FakeItineraryRouter()
        // Same straight-line distance, but the network makes a detour east and back.
        await router.answer { waypoints in
            let detour = Coordinate(latitude: 45.900_5, longitude: 6.121)
            return RoutedPath(waypoints: waypoints, legs: [[waypoints[0], detour, waypoints[1]]])
        }
        let editor = ItineraryEditor(sport: .run, router: router)
        let a = Coordinate(latitude: 45.900, longitude: 6.120)
        let b = Coordinate(latitude: 45.901, longitude: 6.120)

        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await editor.settle()

        // Two hypotenuses of 55.597 m north × 77.384 m east (cos 45.9005°).
        #expect(abs(editor.draft.distance.meters - 2 * 95.284) < 0.1)
    }

    @Test func fastTapsKeepEveryLegJoinedToItsSnappedWaypoints() async {
        let router = FakeItineraryRouter()
        await router.hold()
        let editor = ItineraryEditor(sport: .run, router: router)

        // Both Legs are requested before either answers, so the second one starts
        // from the second Waypoint as placed, not as snapped.
        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        editor.addWaypoint(at: third)
        await router.waitForCalls(2)
        await router.release()
        await editor.settle()

        let waypoints = editor.draft.waypoints.map(\.coordinate)
        #expect(waypoints == [snapped(start), snapped(second), snapped(third)])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed])
        for index in editor.draft.legs.indices {
            let geometry = editor.draft.geometry(ofLegAt: index)
            #expect(geometry.first == waypoints[index])
            #expect(geometry.last == waypoints[index + 1])
        }
    }

    @Test func dismissingTheNoticeClearsIt() async {
        let router = FakeItineraryRouter()
        await router.fail(with: .noPath)
        let editor = ItineraryEditor(sport: .run, router: router)
        editor.addWaypoint(at: start)
        editor.addWaypoint(at: second)
        await editor.settle()

        editor.dismissNotice()

        #expect(editor.notice == nil)
    }
}
