import Foundation
import Testing
@testable import StravaClone

/// The iOS catalog of Itinerary journey events (issue #20, ADR-015): `object_action` names
/// and properties as the API side expects them, never a coordinate.
struct AnalyticsEventTests {
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    @Test func editorOpenedCarriesTheModeAndWhereItWasOpenedFrom() {
        let event = AnalyticsEvent.itineraryEditorOpened(itineraryId: id, mode: .edit, source: .detail)

        #expect(event.name == "itinerary_editor_opened")
        #expect(event.properties == ["itineraryId": "0f8fad5b-d9cb-469f-a165-70867728950e", "mode": "edit", "source": "detail"])
    }

    @Test func firstWaypointCarriesTheSportCode() {
        let event = AnalyticsEvent.itineraryEditorFirstWaypointPlaced(itineraryId: id, sportTypeCode: "ride")

        #expect(event.name == "itinerary_editor_first_waypoint_placed")
        #expect(event.properties == ["itineraryId": .string(id), "sportTypeCode": "ride"])
    }

    @Test func editorClosedCarriesTheOutcomeAndTheSessionCounters() {
        let counters = ItineraryEditorCounters(
            waypointsAdded: 4,
            waypointsMoved: 2,
            waypointsInserted: 1,
            undos: 3,
            redos: 1,
            legsSwitchedToStraight: 1,
            directionsRequests: 9,
            networkFailures: 2,
            noPathResponses: 1,
            rateLimitedResponses: 1
        )
        let event = AnalyticsEvent.itineraryEditorClosed(itineraryId: id, outcome: .saved, hasChanges: true, counters: counters)

        #expect(event.name == "itinerary_editor_closed")
        #expect(event.properties == [
            "itineraryId": .string(id),
            "outcome": "saved",
            "hasChanges": true,
            "waypointsAdded": 4,
            "waypointsMoved": 2,
            "waypointsInserted": 1,
            "undoCount": 3,
            "redoCount": 1,
            "legsSwitchedToStraight": 1,
            "directionsRequests": 9,
            "networkFailures": 2,
            "noPathResponses": 1,
            "rateLimitedResponses": 1,
        ])
    }

    @Test func listDetailAndBlockedEditEvents() {
        #expect(AnalyticsEvent.itineraryRoutingRateLimited(itineraryId: id).name == "itinerary_routing_rate_limited")
        #expect(AnalyticsEvent.itineraryRoutingRateLimited(itineraryId: id).properties == ["itineraryId": .string(id)])

        let list = AnalyticsEvent.itineraryListViewed(source: .mapTab, itineraryCount: 12)
        #expect(list.name == "itinerary_list_viewed")
        #expect(list.properties == ["source": "map_tab", "itineraryCount": 12])

        let detail = AnalyticsEvent.itineraryViewed(itineraryId: id, source: .profile, offline: true)
        #expect(detail.name == "itinerary_viewed")
        #expect(detail.properties == ["itineraryId": .string(id), "source": "profile", "offline": true])

        let blocked = AnalyticsEvent.itineraryOfflineEditBlocked(action: .create)
        #expect(blocked.name == "itinerary_offline_edit_blocked")
        #expect(blocked.properties == ["action": "create"])
    }

    @Test func propertiesBecomePlainValuesForTheSDK() {
        let event = AnalyticsEvent.itineraryViewed(itineraryId: id, source: .mapTab, offline: false)

        let plain = event.properties.mapValues(\.plainValue)

        #expect(plain["source"] as? String == "map_tab")
        #expect(plain["offline"] as? Bool == false)
        #expect(AnalyticsValue.int(3).plainValue as? Int == 3)
    }
}
