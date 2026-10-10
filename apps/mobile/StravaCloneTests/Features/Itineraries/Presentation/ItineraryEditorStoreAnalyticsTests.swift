import Foundation
import Testing
@testable import StravaClone

/// Journey events of an editor session (issue #20, ADR-030 §10), through a fake
/// `AnalyticsClient`: opened, first Waypoint, first `429`, closed with its counters. All are
/// linked by the Itinerary's id and none carries a coordinate.
@MainActor
struct ItineraryEditorStoreAnalyticsTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.120)
    private let id = ItineraryID.fixture(7)

    private func makeStore(
        analytics: FakeAnalyticsClient,
        router: FakeItineraryRouter = FakeItineraryRouter(),
        mode: AnalyticsEvent.EditorMode = .create,
        source: AnalyticsEvent.EditorSource = .mapTab
    ) -> ItineraryEditorStore {
        ItineraryEditorStore(
            editor: ItineraryEditor(
                sport: .ride,
                router: router,
                pauseDelay: .seconds(60),
                sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            ),
            tracking: ItineraryEditorTracking(analytics: analytics, itineraryID: id, mode: mode, source: source)
        )
    }

    @Test func openingTheEditorIsSentOnceWithItsModeAndSource() {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(analytics: analytics, source: .profile)

        store.opened()
        store.opened()

        #expect(analytics.events == [.itineraryEditorOpened(itineraryId: id.description, mode: .create, source: .profile)])
    }

    @Test func theFirstWaypointIsSentOnceWithTheSport() async {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(analytics: analytics)

        store.tap(at: a)
        store.undo()
        store.tap(at: a)
        store.tap(at: b)
        await store.editor.settle()

        #expect(analytics.events(named: "itinerary_editor_first_waypoint_placed") == [
            .itineraryEditorFirstWaypointPlaced(itineraryId: id.description, sportTypeCode: "ride"),
        ])
    }

    @Test func closingAfterSavingSendsTheOutcomeAndTheSessionCounters() async {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(analytics: analytics)
        store.opened()
        store.tap(at: a)
        store.tap(at: b)
        await store.editor.settle()
        store.undo()
        store.redo()
        await store.editor.settle()

        store.closed(.saved)
        store.closed(.abandoned)

        #expect(analytics.events(named: "itinerary_editor_closed") == [
            .itineraryEditorClosed(
                itineraryId: id.description,
                outcome: .saved,
                hasChanges: true,
                counters: ItineraryEditorCounters(waypointsAdded: 2, undos: 1, redos: 1, directionsRequests: 1)
            ),
        ])
    }

    @Test func closingWithoutChangesIsAnAbandonWithoutChanges() async {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(analytics: analytics)
        store.tap(at: a)
        store.undo()

        store.closed(.abandoned)

        guard case .itineraryEditorClosed(_, let outcome, let hasChanges, _)? = analytics.events.last else {
            Issue.record("No closed event")
            return
        }
        #expect(outcome == .abandoned)
        #expect(!hasChanges)
    }

    @Test func onlyTheFirstRateLimitedAnswerOfTheSessionIsSent() async {
        let analytics = FakeAnalyticsClient()
        let router = FakeItineraryRouter()
        let store = makeStore(analytics: analytics, router: router)
        await router.fail(with: .rateLimited)

        store.tap(at: a)
        store.tap(at: b)
        await store.editor.settle()
        store.tap(at: c)
        await store.editor.settle()

        #expect(store.editor.counters.rateLimitedResponses == 2)
        #expect(analytics.events(named: "itinerary_routing_rate_limited") == [
            .itineraryRoutingRateLimited(itineraryId: id.description),
        ])
    }

    @Test func noEventCarriesACoordinate() async {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(analytics: analytics)
        store.opened()
        store.tap(at: a)
        store.tap(at: b)
        await store.editor.settle()
        store.closed(.saved)

        let values = analytics.events.flatMap(\.properties.values)
        #expect(!values.isEmpty)
        for value in values {
            if case .string(let text) = value {
                #expect(!text.contains("45.9"))
                #expect(!text.contains("6.12"))
            }
        }
    }
}
