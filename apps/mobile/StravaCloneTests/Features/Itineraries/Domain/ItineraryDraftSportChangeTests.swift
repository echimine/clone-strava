import Foundation
import Testing
@testable import StravaClone

/// Changing the sport while editing (ADR-030 §2): within a category nothing is requested;
/// across categories the `follow` Legs are requested again in batches of at most 25 points
/// that share their junction Waypoint. Waypoints sit on the fake network's 0.001° grid.
struct ItineraryDraftSportChangeTests {
    /// Grid node `index` steps north of the first one, exact as the fake network snaps it.
    private func point(_ index: Int) -> Coordinate {
        Coordinate(latitude: Double(45_900 + index) / 1_000, longitude: 6.12)
    }

    /// A draft through `count` Waypoints, every Leg routed by the fake network.
    private func routedDraft(sport: ItinerarySport = .run, waypoints count: Int) -> ItineraryDraft {
        var draft = ItineraryDraft(sport: sport)
        for index in 0 ..< count {
            if let request = draft.appendWaypoint(at: point(index)) {
                _ = draft.apply(FakeItineraryRouter.gridPath(request.waypoints), to: request)
            }
        }
        return draft
    }

    @Test func aSportOfTheSameCategoryRequestsNothing() {
        var draft = routedDraft(sport: .run, waypoints: 3)
        let legs = draft.legs

        let requests = draft.changeSport(to: .hike)

        #expect(requests.isEmpty)
        #expect(draft.sport == .hike)
        #expect(draft.legs == legs)
    }

    @Test func anotherCategoryRequestsEachRunOfFollowLegsInBatchesOfAtMost25Points() throws {
        // 60 Waypoints: Legs 0–49 follow, Leg 50 straight, Legs 51–58 follow.
        var draft = routedDraft(sport: .run, waypoints: 60)
        _ = draft.setMode(.straight, ofLeg: draft.legs[50].id)

        let requests = draft.changeSport(to: .ride)

        #expect(draft.sport == .ride)
        #expect(requests.map(\.waypoints) == [
            (0 ... 24).map(point),
            (24 ... 48).map(point),
            (48 ... 50).map(point),
            (51 ... 59).map(point),
        ])
        #expect(requests.allSatisfy { $0.profile == .cycling })
        #expect(requests.flatMap(\.targets).map(\.legID) == draft.legs.filter { $0.mode == .follow }.map(\.id))
        #expect(draft.legs.map(\.state) == Array(repeating: .computing, count: 50) + [.computed] + Array(repeating: .computing, count: 8))
    }

    // MARK: Junction between batches

    /// Where each batch snaps the junction Waypoint 24: a few meters apart.
    private let snappedByFirst = Coordinate(latitude: 45.924, longitude: 6.120_02)
    private let snappedBySecond = Coordinate(latitude: 45.924, longitude: 6.120_05)

    /// An answer that keeps the Waypoints in place except those in `snapped`, one straight
    /// geometry per Leg.
    private func answer(_ request: LegRoutingRequest, snapping snapped: [Int: Coordinate] = [:]) -> RoutedPath {
        let waypoints = request.waypoints.enumerated().map { snapped[$0.offset] ?? $0.element }
        return RoutedPath(waypoints: waypoints, legs: zip(waypoints, waypoints.dropFirst()).map { [$0, $1] })
    }

    /// A draft through 30 Waypoints switched to cycling, and its two batches: 0–24 and 24–29.
    private func switchedToCycling() throws -> (draft: ItineraryDraft, first: LegRoutingRequest, second: LegRoutingRequest) {
        var draft = routedDraft(sport: .walk, waypoints: 30)
        let requests = draft.changeSport(to: .ride)
        try #require(requests.count == 2)
        return (draft, requests[0], requests[1])
    }

    @Test func theJunctionTakesThePositionSnappedByTheFirstBatchAndTheSecondGetsAConnector() throws {
        var (draft, first, second) = try switchedToCycling()

        #expect(draft.apply(answer(first, snapping: [24: snappedByFirst]), to: first) == .applied(followUps: []))
        #expect(draft.apply(answer(second, snapping: [0: snappedBySecond]), to: second) == .applied(followUps: []))

        #expect(draft.waypoints[24].coordinate == snappedByFirst)
        #expect(draft.legs[23].path == [point(23), snappedByFirst])
        #expect(draft.legs[24].path == [snappedByFirst, snappedBySecond, point(25)])
        #expect(draft.legs.allSatisfy { $0.state == .computed })
    }

    @Test func theFirstBatchStillSnapsTheJunctionWhenItAnswersLast() throws {
        var (draft, first, second) = try switchedToCycling()

        #expect(draft.apply(answer(second, snapping: [0: snappedBySecond]), to: second) == .applied(followUps: []))
        #expect(draft.apply(answer(first, snapping: [24: snappedByFirst]), to: first) == .applied(followUps: []))

        #expect(draft.waypoints[24].coordinate == snappedByFirst)
        #expect(draft.legs[23].path == [point(23), snappedByFirst])
        #expect(draft.legs[24].path == [snappedByFirst, snappedBySecond, point(25)])
        #expect(draft.legs.allSatisfy { $0.state == .computed })
    }

    @Test func noConnectorIsAddedWhenBothBatchesSnapTheJunctionAlike() throws {
        var (draft, first, second) = try switchedToCycling()

        _ = draft.apply(answer(second, snapping: [0: snappedByFirst]), to: second)
        _ = draft.apply(answer(first, snapping: [24: snappedByFirst]), to: first)

        #expect(draft.waypoints[24].coordinate == snappedByFirst)
        #expect(draft.legs[24].path == [snappedByFirst, point(25)])
    }

    @Test func aBatchWithNoPathIsRequestedLegByLegStillSharingItsJunction() throws {
        var (draft, first, second) = try switchedToCycling()

        let resolution = draft.fail(.noPath, for: second)
        guard case .applied(let followUps) = resolution else {
            Issue.record("Expected follow-ups, got \(resolution)")
            return
        }

        #expect(followUps.map(\.waypoints) == (24 ... 28).map { [point($0), point($0 + 1)] })
        #expect(followUps.allSatisfy { $0.profile == .cycling })
        #expect(draft.legs[24 ... 28].allSatisfy { $0.mode == .follow && $0.state == .computing })

        _ = draft.apply(answer(first, snapping: [24: snappedByFirst]), to: first)
        _ = draft.apply(answer(followUps[0], snapping: [0: snappedBySecond]), to: followUps[0])

        #expect(draft.waypoints[24].coordinate == snappedByFirst)
        #expect(draft.legs[24].path == [snappedByFirst, snappedBySecond, point(25)])
    }
}
