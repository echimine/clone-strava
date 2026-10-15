import Foundation

/// The path the app works out from the athlete's position back onto the Itinerary they left
/// (ADR-031 §7, "Chemin recalculé"). Never part of the Activity; saved with the Recording.
struct ReturnPath: Equatable, Sendable {
    /// From where it was asked to the return point, as the router drew it.
    let path: [Coordinate]
    /// Length measured by the router.
    let distance: Distance
    /// Where it meets the Itinerary again.
    let returnPoint: ItineraryProgress.ReturnPoint
}

/// A Return path to ask the router for.
struct ReturnPathRequest: Equatable, Sendable {
    /// Tells an answer to a request still awaited from a late answer to an abandoned one.
    let id: Int
    let position: Coordinate
    let returnPoint: ItineraryProgress.ReturnPoint
    /// GPS course ± 45°, `nil` when invalid.
    let bearing: Bearing?
}

/// What the Recording has to do with the router after an event.
enum ReturnPathCommand: Equatable, Sendable {
    case send(ReturnPathRequest)
    /// Back on the Itinerary, or it is finished: the request in flight is no longer wanted.
    case cancel
}

/// When to ask for a Return path (ADR-031 §7), as pure rules: the athlete leaves the
/// Itinerary (or the Return path) after 3 accurate points in a row more than 50 m away over at
/// least 10 s; at least 30 s between two requests, at most 5 per departure, a temporary failure
/// or a `429` retried after 30 s, no route or too many requests: offline mode until re-snapping.
/// Nothing here is saved: a resumed Recording starts a fresh count.
struct ReturnPathRules: Equatable, Sendable {
    static let departureDistanceM = ItineraryProgress.snapRadiusM
    static let departurePoints = 3
    static let departureDuration: TimeInterval = 10
    static let minimumInterval: TimeInterval = 30
    static let retryDelay: TimeInterval = 30
    static let maxRequestsPerDeparture = 5

    /// Accurate points in a row away from the track and the Return path.
    private struct Streak: Equatable, Sendable {
        var count: Int
        let since: Date
    }

    /// Off the Itinerary for good: "Hors Itinéraire" until re-snapping.
    private(set) var isDeparted: Bool
    private(set) var inFlight: ReturnPathRequest?
    private(set) var isOnline = true
    private var streak: Streak?
    private var wantsPath = false
    /// No route, or 5 requests already: offline mode until re-snapping.
    private var gaveUp = false
    private var requestCount = 0
    private var lastRequestAt: Date?
    private var retryAt: Date?
    private var nextID = 1

    /// - Parameter isDeparted: a Return path read back from storage means the athlete had left.
    init(isDeparted: Bool = false) {
        self.isDeparted = isDeparted
    }

    /// An accurate fix off the track; `isAway` when also more than 50 m from the Return path.
    mutating func observe(at time: Date, isAway: Bool) {
        guard isAway else {
            streak = nil
            return
        }
        var streak = streak ?? Streak(count: 0, since: time)
        streak.count += 1
        if streak.count >= Self.departurePoints, time.timeIntervalSince(streak.since) >= Self.departureDuration {
            self.streak = nil
            isDeparted = true
            wantsPath = true
        } else {
            self.streak = streak
        }
    }

    /// Whether a request may leave now; past the cap, offline mode.
    mutating func isRequestDue(at time: Date) -> Bool {
        guard wantsPath, !gaveUp, inFlight == nil, isOnline else { return false }
        guard requestCount < Self.maxRequestsPerDeparture else {
            gaveUp = true
            return false
        }
        if let retryAt, time < retryAt { return false }
        if let lastRequestAt, time.timeIntervalSince(lastRequestAt) < Self.minimumInterval { return false }
        return true
    }

    mutating func makeRequest(position: Coordinate, returnPoint: ItineraryProgress.ReturnPoint, bearing: Bearing?, at time: Date) -> ReturnPathRequest {
        let request = ReturnPathRequest(id: nextID, position: position, returnPoint: returnPoint, bearing: bearing)
        nextID += 1
        requestCount += 1
        lastRequestAt = time
        retryAt = nil
        wantsPath = false
        inFlight = request
        return request
    }

    /// `true` when `request` was the one awaited.
    mutating func arrived(for request: ReturnPathRequest) -> Bool {
        guard inFlight?.id == request.id else { return false }
        inFlight = nil
        streak = nil
        return true
    }

    /// `true` when `request` was the one awaited.
    mutating func failed(_ error: RoutingError, for request: ReturnPathRequest, at time: Date) -> Bool {
        guard inFlight?.id == request.id else { return false }
        inFlight = nil
        switch error {
        case .noPath:
            gaveUp = true
        case .temporary, .rateLimited:
            wantsPath = true
            retryAt = time.addingTimeInterval(Self.retryDelay)
        }
        return true
    }

    mutating func connectivityChanged(_ isOnline: Bool) {
        self.isOnline = isOnline
    }

    /// Back on the track: everything starts again, the network state excepted.
    mutating func reset() {
        let isOnline = isOnline
        let nextID = nextID
        self = ReturnPathRules()
        self.isOnline = isOnline
        self.nextID = nextID
    }

    /// When a request still wanted may leave on time alone (30 s after the previous one, or
    /// after a temporary failure), so it leaves even if no fix comes; `nil` when none waits.
    var nextRequestDate: Date? {
        guard wantsPath, !gaveUp, inFlight == nil, isOnline, requestCount < Self.maxRequestsPerDeparture else {
            return nil
        }
        return [retryAt, lastRequestAt?.addingTimeInterval(Self.minimumInterval)].compactMap(\.self).max()
    }

    /// Something to cancel or to clear on re-snapping.
    var isIdle: Bool {
        !isDeparted && inFlight == nil && streak == nil
    }
}
