import Foundation
import Testing
@testable import StravaClone

struct CelebrationRouteTests {
    /// 111 m north then 333 m east, on the equator: the corner is at a quarter of the length.
    private let corner = [
        Coordinate(latitude: 0, longitude: 0),
        Coordinate(latitude: 0.001, longitude: 0),
        Coordinate(latitude: 0.001, longitude: 0.003),
    ]

    /// ADR-032 §5: the trace's head moves along the trace as the draw progresses, measured on
    /// the map's length like the line's trim, so the head sits at the drawn line's tip.
    @Test func theHeadMovesAlongTheTraceByLength() throws {
        let route = CelebrationRoute(trace: corner)

        expectClose(try #require(route.head(at: 0)), Coordinate(latitude: 0, longitude: 0))
        expectClose(try #require(route.head(at: 0.125)), Coordinate(latitude: 0.0005, longitude: 0))
        expectClose(try #require(route.head(at: 0.25)), Coordinate(latitude: 0.001, longitude: 0))
        expectClose(try #require(route.head(at: 0.5)), Coordinate(latitude: 0.001, longitude: 0.001))
        expectClose(try #require(route.head(at: 1)), Coordinate(latitude: 0.001, longitude: 0.003))
    }

    /// Progress outside 0...1 (an eased curve overshooting) stays on the trace's ends.
    @Test func theHeadStaysOnTheTraceOutsideZeroToOne() throws {
        let route = CelebrationRoute(trace: corner)

        expectClose(try #require(route.head(at: -0.2)), corner[0])
        expectClose(try #require(route.head(at: 1.3)), corner[2])
    }

    @Test func aTraceWithoutTwoPointsHasNoHead() {
        #expect(CelebrationRoute(trace: []).head(at: 0.5) == nil)
        #expect(CelebrationRoute(trace: [corner[0]]).head(at: 0.5) == corner[0])
    }

    /// ADR-032 §5: the camera follows a simplified trace, so GPS wiggles do not shake it.
    @Test func theCameraPathDropsWigglesSmallerThanTheOuting() {
        // 2 km north with 3 m sideways wiggles every 20 m.
        let wiggly = (0...100).map { index in
            Coordinate(latitude: 45 + Double(index) * 0.00018, longitude: 4.8 + (index.isMultiple(of: 2) ? 0 : 0.00004))
        }

        let path = CelebrationRoute(trace: wiggly).cameraPath

        #expect(path == [wiggly[0], wiggly[100]])
    }

    /// The outing's real turns stay in the camera path, its start and finish too.
    @Test func theCameraPathKeepsTheOutingsTurns() throws {
        let ride = try SharedTrace.named("ride-long-loop.json").samples.map(\.coordinate)

        let path = CelebrationRoute(trace: ride).cameraPath

        // 320 legs north, 200 east, 320 south, 200 west: the start, three corners, the finish.
        #expect(path == [ride[0], ride[320], ride[520], ride[840], ride[1040]])
    }

    /// The camera's centre moves along the simplified path from the start to the finish.
    @Test func theCameraCentreGoesFromStartToFinish() throws {
        let route = CelebrationRoute(trace: corner)

        expectClose(try #require(route.cameraCenter(at: 0)), corner[0])
        expectClose(try #require(route.cameraCenter(at: 1)), corner[2])
    }

    /// The camera follows from high enough to show most of the outing (and to look over the
    /// slopes around a valley): a 52 km ride, a 16 × 10 km box, from zoom ~10.46; a short loop
    /// no closer than the neighbourhood.
    @Test func theFollowZoomShowsMostOfTheOuting() throws {
        let ride = try SharedTrace.named("ride-long-loop.json").samples.map(\.coordinate)
        let run = try SharedTrace.named("run-no-pause.json").samples.map(\.coordinate)

        #expect(abs(CelebrationRoute(trace: ride).followZoom - 10.46) < 0.02)
        #expect(CelebrationRoute(trace: run).followZoom > CelebrationRoute(trace: ride).followZoom)
        #expect(CelebrationRoute(trace: Array(corner.prefix(2))).followZoom == CelebrationRoute.followZooms.upperBound)
        #expect(CelebrationRoute(trace: [corner[0]]).followZoom == CelebrationRoute.followZooms.upperBound)
    }

    /// ADR-032 §5, #83: a 52 km ride plays in the same 10 s as a 1.8 km run: at the moment the
    /// timeline marks the trace drawn, both heads are on their finish.
    @Test func aLongOutingIsDrawnInTheSameTimeAsAShortOne() throws {
        let drawn = CelebrationTimeline.frame(at: CelebrationTimeline.traceDrawnAt).traceProgress
        for name in ["ride-long-loop.json", "run-no-pause.json"] {
            let trace = try SharedTrace.named(name).samples.map(\.coordinate)
            let route = CelebrationRoute(trace: trace)

            expectClose(try #require(route.head(at: drawn)), try #require(trace.last))
            expectClose(try #require(route.cameraCenter(at: drawn)), try #require(trace.last))
        }
    }

    private func expectClose(_ actual: Coordinate, _ expected: Coordinate, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual.latitude - expected.latitude) < 1e-9, sourceLocation: sourceLocation)
        #expect(abs(actual.longitude - expected.longitude) < 1e-9, sourceLocation: sourceLocation)
    }
}
