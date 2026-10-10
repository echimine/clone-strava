import Foundation
import Testing
@testable import StravaClone

/// The editor state as a pure value (ADR-030 §2): a router answer is applied only while
/// the Legs it covers keep the version and endpoints they had when it was asked.
struct ItineraryDraftTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let x = Coordinate(latitude: 45.904_2, longitude: 6.123_8)
    private let y = Coordinate(latitude: 45.905_1, longitude: 6.118_9)

    private func answer(_ request: LegRoutingRequest) -> RoutedPath {
        FakeItineraryRouter.gridPath(request.waypoints)
    }

    @Test func anAnswerForEndpointsThatMovedSinceIsStale() throws {
        var draft = ItineraryDraft(sport: .run)
        _ = draft.appendWaypoint(at: a)
        let appended = draft.appendWaypoint(at: b)
        let first = try #require(appended)
        _ = draft.apply(answer(first), to: first)
        let finish = draft.waypoints[1].id

        draft.moveWaypoint(finish, to: x)
        let request = draft.routeLegs(around: finish)
        let overtaken = try #require(request)
        draft.moveWaypoint(finish, to: y)
        let before = draft

        #expect(draft.apply(answer(overtaken), to: overtaken) == .stale)
        #expect(draft == before)
    }

    @Test func anAnswerForAnOlderVersionIsStaleEvenWithTheSameEndpoints() throws {
        var draft = ItineraryDraft(sport: .run)
        _ = draft.appendWaypoint(at: a)
        let appended = draft.appendWaypoint(at: b)
        let first = try #require(appended)
        let leg = draft.legs[0].id

        // Same Waypoints, but the Leg went straight and back: its version moved on.
        _ = draft.setMode(.straight, ofLeg: leg)
        let followed = draft.setMode(.follow, ofLeg: leg)
        let current = try #require(followed)
        #expect(current.waypoints == first.waypoints)

        #expect(draft.apply(answer(first), to: first) == .stale)
        #expect(draft.legs[0].state == .computing)
        #expect(draft.apply(answer(current), to: current) == .applied(followUps: []))
        #expect(draft.legs[0].state == .computed)
    }
}
