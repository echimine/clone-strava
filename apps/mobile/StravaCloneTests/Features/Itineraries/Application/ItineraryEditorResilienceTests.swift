import Foundation
import Testing
@testable import StravaClone

/// The editor keeps working when routing fails (ADR-030 §2): pending Legs, retries when the
/// network comes back, backoff on `429`, and the 200-Waypoint cap. Waypoints sit on the fake
/// network's 0.001° grid, so a routed Leg keeps them in place.
@MainActor
struct ItineraryEditorResilienceTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let d = Coordinate(latitude: 45.903, longitude: 6.122)

    /// Delays the editor asked to wait before retrying, without actually waiting.
    private final class RecordingSleeper: @unchecked Sendable {
        let delays = Locked<[Duration]>([])

        var sleep: @Sendable (Duration) async throws -> Void {
            { [delays] delay in delays.value.append(delay) }
        }
    }

    private func makeEditor(
        router: FakeItineraryRouter,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(1), maxDelay: .seconds(60)),
        sleeper: RecordingSleeper = RecordingSleeper()
    ) -> ItineraryEditor {
        ItineraryEditor(sport: .run, router: router, pauseDelay: .seconds(60), backoff: backoff, sleep: sleeper.sleep)
    }

    private func add(_ points: [Coordinate], to editor: ItineraryEditor) async {
        for point in points {
            editor.addWaypoint(at: point)
            await editor.settle()
        }
    }

    /// Connectivity values already emitted, then the end of the stream.
    private func connectivity(_ values: Bool...) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    // MARK: Pending Legs

    @Test func aTemporaryFailurePendsItsLegWithoutBlockingOtherGestures() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await router.fail(with: .temporary)
        await add([a, b], to: editor)
        #expect(editor.draft.legs.map(\.state) == [.pending])

        await router.answer(with: FakeItineraryRouter.gridPath)
        await add([c, d], to: editor)

        #expect(editor.draft.legs.map(\.state) == [.pending, .computed, .computed])
        #expect(editor.draft.legs.map(\.mode) == [.follow, .follow, .follow])

        editor.setMode(.straight, ofLeg: editor.draft.legs[2].id)
        editor.removeWaypoint(editor.draft.waypoints[2].id)
        await editor.settle()
        #expect(editor.draft.waypoints.map(\.coordinate) == [a, b, d])
        #expect(editor.draft.legs.map(\.mode) == [.follow, .follow])
        #expect(editor.draft.legs.map(\.state) == [.pending, .computed])

        editor.undo()
        #expect(editor.draft.waypoints.count == 4)
    }

    @Test func savingIsBlockedWhileALegIsPendingAndAllowedOnceItIsComputed() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await router.fail(with: .temporary)
        await add([a, b], to: editor)

        #expect(editor.draft.saveIssue == .legsPending)

        await router.answer(with: FakeItineraryRouter.gridPath)
        await editor.retryPendingLegs(onReconnectionOf: connectivity(false, true))
        await editor.settle()

        #expect(editor.draft.legs.map(\.state) == [.computed])
        #expect(editor.draft.saveIssue == nil)
    }

    // MARK: Network back

    @Test func pendingLegsAreRequestedAgainWhenTheNetworkComesBack() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await router.fail(with: .temporary)
        await add([a, b], to: editor)

        await router.answer(with: FakeItineraryRouter.gridPath)
        await editor.retryPendingLegs(onReconnectionOf: connectivity(true, false, true))
        await editor.settle()

        #expect(await router.calls.map(\.waypoints) == [[a, b], [a, b]])
        #expect(editor.draft.legs.map(\.state) == [.computed])
        #expect(editor.draft.geometry(ofLegAt: 0) == [a, Coordinate(latitude: a.latitude, longitude: b.longitude), b])
    }

    @Test func theCurrentStateOfTheNetworkIsNotAReturn() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await router.fail(with: .temporary)
        await add([a, b], to: editor)

        await editor.retryPendingLegs(onReconnectionOf: connectivity(true))
        await editor.settle()

        #expect(await router.calls.count == 1)
        #expect(editor.draft.legs.map(\.state) == [.pending])
    }

    @Test func consecutivePendingLegsAreRequestedTogether() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await add([a, b], to: editor)
        await router.fail(with: .temporary)
        await add([c, d], to: editor)
        #expect(editor.draft.legs.map(\.state) == [.computed, .pending, .pending])

        await router.answer(with: FakeItineraryRouter.gridPath)
        await editor.retryPendingLegs(onReconnectionOf: connectivity(false, true))
        await editor.settle()

        #expect(await router.calls.dropFirst(3).map(\.waypoints) == [[b, c, d]])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed, .computed])
    }

    @Test func pendingLegsCanBeRetriedOnDemand() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        await router.fail(with: .temporary)
        await add([a, b], to: editor)

        await router.answer(with: FakeItineraryRouter.gridPath)
        editor.retryPendingLegs()
        await editor.settle()

        #expect(editor.draft.legs.map(\.state) == [.computed])
        #expect(!editor.hasPendingLegs)
    }

    // MARK: Saturation

    @Test func aRateLimitedLegIsRetriedWithExponentialBackoff() async {
        let router = FakeItineraryRouter()
        let sleeper = RecordingSleeper()
        let editor = makeEditor(router: router, sleeper: sleeper)
        let refusals = Locked(3)
        await router.answer { waypoints in
            guard refusals.value == 0 else {
                refusals.value -= 1
                throw RoutingError.rateLimited
            }
            return FakeItineraryRouter.gridPath(waypoints)
        }

        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await router.waitForCalls(4)
        await editor.settle()

        #expect(sleeper.delays.value == [.seconds(1), .seconds(2), .seconds(4)])
        #expect(editor.draft.legs.map(\.state) == [.computed])
        // Nothing is pending anymore: the saturation message is gone.
        #expect(editor.notice == nil)

        // A success resets the backoff.
        refusals.value = 1
        editor.addWaypoint(at: c)
        await router.waitForCalls(6)
        await editor.settle()
        #expect(sleeper.delays.value == [.seconds(1), .seconds(2), .seconds(4), .seconds(1)])
        #expect(editor.draft.legs.map(\.state) == [.computed, .computed])
    }

    @Test func theBackoffIsCapped() async {
        let router = FakeItineraryRouter()
        let sleeper = RecordingSleeper()
        let editor = makeEditor(
            router: router,
            backoff: RetryBackoff(initialDelay: .seconds(1), maxDelay: .seconds(3)),
            sleeper: sleeper
        )
        let refusals = Locked(4)
        await router.answer { waypoints in
            guard refusals.value == 0 else {
                refusals.value -= 1
                throw RoutingError.rateLimited
            }
            return FakeItineraryRouter.gridPath(waypoints)
        }

        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await router.waitForCalls(5)
        await editor.settle()

        #expect(sleeper.delays.value == [.seconds(1), .seconds(2), .seconds(3), .seconds(3)])
    }

    // MARK: Waypoint cap

    @Test func the201stWaypointIsRefusedWithAMessage() async {
        let router = FakeItineraryRouter()
        let editor = makeEditor(router: router)
        let points = (0 ..< ItineraryDraft.maxWaypoints).map {
            Coordinate(latitude: 45.900 + Double($0) * 0.001, longitude: 6.120)
        }
        await add(points, to: editor)
        #expect(editor.draft.waypoints.count == 200)
        #expect(editor.notice == nil)

        editor.addWaypoint(at: Coordinate(latitude: 46.200, longitude: 6.120))
        #expect(editor.draft.waypoints.count == 200)
        #expect(editor.notice == .waypointLimitReached)

        editor.dismissNotice()
        editor.beginInsertion(intoLeg: editor.draft.legs[0].id, at: Coordinate(latitude: 45.900_5, longitude: 6.121))
        editor.endDrag()
        #expect(editor.draft.waypoints.count == 200)
        #expect(editor.draggedWaypointID == nil)
        #expect(editor.notice == .waypointLimitReached)

        // Once a Waypoint is removed, there is room again.
        editor.removeWaypoint(editor.draft.waypoints[199].id)
        editor.addWaypoint(at: Coordinate(latitude: 46.200, longitude: 6.120))
        #expect(editor.draft.waypoints.count == 200)
    }
}
