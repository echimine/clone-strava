import Foundation

/// Typed catalog of the events the app sends (ADR-015): `object_action` names in the past
/// tense, no free-form strings in the code. Itinerary journey events follow issue #20 and
/// ADR-030 §10; the API sends the lifecycle ones. Properties are rounded and never hold a
/// coordinate: `AnalyticsValue` has no floating-point case. `itineraryId` is the id the app
/// generates, the one the API events carry too.
enum AnalyticsEvent: Equatable, Sendable {
    /// The editor creates a new Itinerary, or reopens a saved one ("Modifier").
    enum EditorMode: String, Sendable {
        case create, edit
    }

    /// Where the editor was opened from.
    enum EditorSource: String, Sendable {
        case mapTab = "map_tab", profile, detail, recording
    }

    /// Where a list or a detail is shown.
    enum ListSource: String, Sendable {
        case mapTab = "map_tab", profile
    }

    enum EditorOutcome: String, Sendable {
        case saved, abandoned
    }

    case itineraryEditorOpened(itineraryId: String, mode: EditorMode, source: EditorSource)
    case itineraryEditorFirstWaypointPlaced(itineraryId: String, sportTypeCode: String)
    /// Gestures are measured by the session counters, not one event each.
    case itineraryEditorClosed(itineraryId: String, outcome: EditorOutcome, hasChanges: Bool, counters: ItineraryEditorCounters)
    /// First `429` from the router in an editor session.
    case itineraryRoutingRateLimited(itineraryId: String)
    case itineraryListViewed(source: ListSource, itineraryCount: Int)
    case itineraryViewed(itineraryId: String, source: ListSource, offline: Bool)
    /// "Créer" or "Modifier" offline: "Connexion requise".
    case itineraryOfflineEditBlocked(action: EditorMode)

    var name: String {
        switch self {
        case .itineraryEditorOpened: "itinerary_editor_opened"
        case .itineraryEditorFirstWaypointPlaced: "itinerary_editor_first_waypoint_placed"
        case .itineraryEditorClosed: "itinerary_editor_closed"
        case .itineraryRoutingRateLimited: "itinerary_routing_rate_limited"
        case .itineraryListViewed: "itinerary_list_viewed"
        case .itineraryViewed: "itinerary_viewed"
        case .itineraryOfflineEditBlocked: "itinerary_offline_edit_blocked"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .itineraryEditorOpened(let id, let mode, let source):
            ["itineraryId": .string(id), "mode": .string(mode.rawValue), "source": .string(source.rawValue)]
        case .itineraryEditorFirstWaypointPlaced(let id, let sportTypeCode):
            ["itineraryId": .string(id), "sportTypeCode": .string(sportTypeCode)]
        case .itineraryEditorClosed(let id, let outcome, let hasChanges, let counters):
            counters.properties.merging([
                "itineraryId": .string(id),
                "outcome": .string(outcome.rawValue),
                "hasChanges": .bool(hasChanges),
            ]) { _, new in new }
        case .itineraryRoutingRateLimited(let id):
            ["itineraryId": .string(id)]
        case .itineraryListViewed(let source, let count):
            ["source": .string(source.rawValue), "itineraryCount": .int(count)]
        case .itineraryViewed(let id, let source, let offline):
            ["itineraryId": .string(id), "source": .string(source.rawValue), "offline": .bool(offline)]
        case .itineraryOfflineEditBlocked(let action):
            ["action": .string(action.rawValue)]
        }
    }
}

/// What happened during one editor session, sent when the editor closes (issue #20).
struct ItineraryEditorCounters: Equatable, Sendable {
    var waypointsAdded = 0
    var waypointsMoved = 0
    /// Waypoints inserted by pulling a Leg's middle.
    var waypointsInserted = 0
    var undos = 0
    var redos = 0
    /// Legs the athlete switched to a straight line.
    var legsSwitchedToStraight = 0
    var directionsRequests = 0
    /// Router answers: network failure, timeout or server error.
    var networkFailures = 0
    var noPathResponses = 0
    /// `429` answers.
    var rateLimitedResponses = 0

    fileprivate var properties: [String: AnalyticsValue] {
        [
            "waypointsAdded": .int(waypointsAdded),
            "waypointsMoved": .int(waypointsMoved),
            "waypointsInserted": .int(waypointsInserted),
            "undoCount": .int(undos),
            "redoCount": .int(redos),
            "legsSwitchedToStraight": .int(legsSwitchedToStraight),
            "directionsRequests": .int(directionsRequests),
            "networkFailures": .int(networkFailures),
            "noPathResponses": .int(noPathResponses),
            "rateLimitedResponses": .int(rateLimitedResponses),
        ]
    }
}

/// An event property. Whole numbers only: values are rounded before they get here, and a
/// coordinate cannot be expressed.
enum AnalyticsValue: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case bool(Bool)

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    /// The value as an analytics SDK takes it.
    var plainValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}
