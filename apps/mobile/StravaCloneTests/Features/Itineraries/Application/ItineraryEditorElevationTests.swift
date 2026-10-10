import Foundation
import Testing
@testable import StravaClone

/// Live elevation gain (ADR-030 §3): `metrics-preview` is asked on release only, on the
/// full track, with a fake previewer at the Domain protocol. Waypoints sit on the fake
/// network's 0.001° grid, so a routed Leg keeps them in place.
@MainActor
struct ItineraryEditorElevationTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let elsewhere = Coordinate(latitude: 45.905, longitude: 6.125)

    private func makeEditor(
        through points: [Coordinate],
        previewer: FakeItineraryMetricsPreviewer,
        router: FakeItineraryRouter = FakeItineraryRouter()
    ) async -> ItineraryEditor {
        let editor = ItineraryEditor(sport: .run, router: router, metricsPreviewer: previewer, pauseDelay: .seconds(60))
        for point in points {
            editor.addWaypoint(at: point)
            await editor.settle()
        }
        return editor
    }

    private func gridLeg(_ start: Coordinate, _ end: Coordinate) -> ItineraryGeometry.Leg {
        .follow(EncodedPolyline(encoding: [start, Coordinate(latitude: start.latitude, longitude: end.longitude), end], precision: 6))
    }

    @Test func theGainIsPreviewedOnTheFullTrackOnceItsLegsAreRouted() async {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a], previewer: previewer)
        #expect(editor.elevation.status == .idle)

        editor.addWaypoint(at: b)
        #expect(editor.elevation.status == .measuring)
        await editor.settle()

        #expect(await previewer.requests == [
            ItineraryGeometry(waypoints: [a, b], legs: [gridLeg(a, b)]),
        ])
        #expect(editor.elevation.status == .measured)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 20))
    }

    @Test func theGainIsGreyedWhileAWaypointIsDraggedAndMeasuredOnceOnRelease() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a, b], previewer: previewer)
        let finish = try #require(editor.draft.waypoints.last).id

        editor.beginDrag(finish)
        #expect(editor.elevation.status == .measured)

        editor.drag(to: elsewhere)
        editor.drag(to: c)
        #expect(editor.elevation.status == .measuring)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 20))

        editor.endDrag()
        await editor.settle()

        #expect(await previewer.requests.dropFirst().map(\.waypoints) == [[a, c]])
        #expect(editor.elevation.status == .measured)
    }

    @Test func aPauseDuringADragRoutesTheLegsButLeavesTheGainGreyedUntilRelease() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        let router = FakeItineraryRouter()
        let editor = ItineraryEditor(sport: .run, router: router, metricsPreviewer: previewer, pauseDelay: .milliseconds(1))
        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await editor.settle()
        let finish = try #require(editor.draft.waypoints.last).id

        editor.beginDrag(finish)
        editor.drag(to: c)
        await router.waitForCalls(2)
        await editor.settle()

        #expect(await previewer.requests.count == 1)
        #expect(editor.elevation.status == .measuring)

        editor.endDrag()
        await editor.settle()

        #expect(await previewer.requests.map(\.legs) == [[gridLeg(a, b)], [gridLeg(a, c)]])
        #expect(editor.elevation.status == .measured)
    }

    @Test func aFailedPreviewIsUnavailableUntilARetrySucceeds() async {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.fail(with: .unavailable)
        let editor = await makeEditor(through: [a, b], previewer: previewer)

        #expect(editor.elevation.status == .unavailable)

        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 42))
        editor.elevation.retry()
        #expect(editor.elevation.status == .measuring)
        await editor.settle()

        #expect(await previewer.requests.count == 2)
        #expect(await previewer.requests.last == previewer.requests.first)
        #expect(editor.elevation.status == .measured)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 42))
    }

    @Test func editingIsNotBlockedWhileTheGainIsUnavailable() async {
        let previewer = FakeItineraryMetricsPreviewer()
        await previewer.fail(with: .offline)
        let editor = await makeEditor(through: [a, b], previewer: previewer)
        #expect(editor.elevation.status == .unavailable)

        await previewer.answer(FakeItineraryMetricsPreviewer.metrics(gain: 30))
        editor.addWaypoint(at: c)
        await editor.settle()

        #expect(editor.draft.waypoints.count == 3)
        #expect(editor.elevation.status == .measured)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 30))
    }

    @Test func anAnswerArrivingAfterTheNextGestureStartedIsDropped() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a, b], previewer: previewer)
        await previewer.hold()

        editor.addWaypoint(at: c)
        await previewer.waitForRequests(2)
        let finish = try #require(editor.draft.waypoints.last).id
        editor.beginDrag(finish)
        editor.drag(to: elsewhere)

        await previewer.release()
        await editor.elevation.settle()

        #expect(editor.elevation.status == .measuring)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 20))
    }

    @Test func anAnswerForATrackUndoneSinceIsDropped() async {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a, b], previewer: previewer)
        await previewer.hold()
        await previewer.answer { request in
            .success(FakeItineraryMetricsPreviewer.metrics(gain: request.waypoints.count == 3 ? 99 : 7))
        }

        editor.addWaypoint(at: c)
        await previewer.waitForRequests(2)
        editor.undo()
        await previewer.release()
        await editor.settle()

        #expect(editor.draft.waypoints.count == 2)
        #expect(editor.elevation.status == .measured)
        #expect(editor.elevation.metrics == FakeItineraryMetricsPreviewer.metrics(gain: 7))
    }

    @Test func removingTheFinishLeavesNothingToMeasure() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a, b], previewer: previewer)

        editor.removeWaypoint(try #require(editor.draft.waypoints.last).id)
        await editor.settle()

        #expect(editor.elevation.status == .idle)
        #expect(editor.elevation.metrics == nil)
        #expect(await previewer.requests.count == 1)
    }

    @Test func pullingAStraightLegIsMeasuredOnlyOnRelease() async throws {
        let previewer = FakeItineraryMetricsPreviewer()
        let editor = await makeEditor(through: [a, b], previewer: previewer)
        let leg = try #require(editor.draft.legs.first).id
        editor.setMode(.straight, ofLeg: leg)
        await editor.settle()
        #expect(await previewer.requests.last?.legs == [.straight])

        editor.beginInsertion(intoLeg: leg, at: elsewhere)
        await editor.settle()

        #expect(await previewer.requests.count == 2)
        #expect(editor.elevation.status == .measuring)

        editor.endDrag()
        await editor.settle()

        #expect(await previewer.requests.last == ItineraryGeometry(waypoints: [a, elsewhere, b], legs: [.straight, .straight]))
        #expect(editor.elevation.status == .measured)
    }
}
