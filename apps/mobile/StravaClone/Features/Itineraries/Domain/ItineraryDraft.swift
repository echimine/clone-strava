import Foundation

struct WaypointID: Hashable, Sendable {
    let rawValue = UUID()
}

struct LegID: Hashable, Sendable {
    let rawValue = UUID()
}

/// A point the athlete places to shape the Itinerary (`CONTEXT.md`).
struct Waypoint: Identifiable, Equatable, Sendable {
    let id: WaypointID
    /// Position shown and saved: snapped to the network by a `follow` Leg, as placed otherwise.
    var coordinate: Coordinate
}

/// How a Leg joins its two Waypoints (ADR-030 §2). A straight line chosen by the athlete
/// and one forced by a missing path are not told apart.
enum LegMode: String, Hashable, Sendable {
    case follow, straight
}

/// Where a Leg's geometry stands.
enum LegState: Hashable, Sendable {
    /// Geometry is final for the Leg's current endpoints and mode.
    case computed
    /// A routing request is in flight.
    case computing
    /// Routing failed for a temporary reason; the Leg still `follow`s and must be retried.
    case pending
}

/// The part of the Itinerary from one Waypoint to the next (`CONTEXT.md`).
/// Leg *n* joins Waypoints *n* and *n + 1*.
struct Leg: Identifiable, Equatable, Sendable {
    let id: LegID
    var mode: LegMode
    /// Geometry from the router. `nil` draws a straight line between the Leg's Waypoints:
    /// a `straight` Leg, or a `follow` Leg not computed yet.
    var path: [Coordinate]?
    /// Bumped whenever the Leg's endpoints or mode change: an answer for an older version is stale.
    var version: Int
    var state: LegState
}

/// Routing work for consecutive `follow` Legs, as they were when it was asked.
struct LegRoutingRequest: Equatable, Sendable {
    struct Target: Equatable, Sendable {
        let legID: LegID
        let version: Int
    }

    let targets: [Target]
    /// The Legs' Waypoints, `targets.count + 1` of them.
    let waypoints: [Coordinate]
    let profile: RoutingProfile

    var legIDs: Set<LegID> { Set(targets.map(\.legID)) }
}

/// What applying a routing answer did to the draft.
enum RoutingResolution: Equatable, Sendable {
    /// The Legs changed since the request: the answer is ignored.
    case stale
    /// The answer was applied; `followUps` must be sent to the router.
    case applied(followUps: [LegRoutingRequest])
}

/// State of the Itinerary editor (ADR-030 §2): a pure value, with no UI and no I/O.
/// Gestures return the routing requests they need; router answers are applied back only
/// while the Legs they cover are unchanged. Being a value, a past state can be kept for undo.
struct ItineraryDraft: Equatable, Sendable {
    private(set) var sport: ItinerarySport
    private(set) var waypoints: [Waypoint] = []
    /// Always `waypoints.count - 1` Legs once there is a start.
    private(set) var legs: [Leg] = []

    init(sport: ItinerarySport) {
        self.sport = sport
    }

    /// Length of the Legs as currently drawn, measured locally.
    var distance: Distance {
        legs.indices.reduce(.zero) { total, index in
            let geometry = geometry(ofLegAt: index)
            return zip(geometry, geometry.dropFirst()).reduce(total) { $0 + $1.0.distance(to: $1.1) }
        }
    }

    /// Geometry of a Leg: the routed path, or a straight line between its Waypoints.
    func geometry(ofLegAt index: Int) -> [Coordinate] {
        legs[index].path ?? [waypoints[index].coordinate, waypoints[index + 1].coordinate]
    }

    // MARK: Gestures

    /// Tap on the map: the first Waypoint is the start; each next one is appended as the
    /// new finish, joined by a `follow` Leg to compute.
    mutating func appendWaypoint(at coordinate: Coordinate) -> LegRoutingRequest? {
        waypoints.append(Waypoint(id: WaypointID(), coordinate: coordinate))
        guard waypoints.count >= 2 else { return nil }
        legs.append(Leg(id: LegID(), mode: .follow, path: nil, version: 0, state: .computing))
        return makeRequest(forLegsIn: legs.count - 1 ... legs.count - 1)
    }

    // MARK: Router answers

    /// A path was found: the Legs take its geometry and their Waypoints the snapped positions.
    /// A Waypoint shared with a Leg outside the request moves only if that Leg has no routed
    /// path yet; the Leg is then requested again from the new position.
    mutating func apply(_ path: RoutedPath, to request: LegRoutingRequest) -> RoutingResolution {
        guard let range = currentRange(of: request) else { return .stale }
        guard path.waypoints.count == request.waypoints.count, path.legs.count == request.targets.count else {
            return fail(.temporary, for: request)
        }
        for (offset, index) in range.enumerated() {
            legs[index].path = path.legs[offset]
            legs[index].state = .computed
        }
        var followUps: [LegRoutingRequest] = []
        let waypointRange = range.lowerBound ... range.upperBound + 1
        for (offset, index) in waypointRange.enumerated() where waypoints[index].coordinate != path.waypoints[offset] {
            let outsideLeg = index == range.lowerBound ? index - 1 : (index == waypointRange.upperBound ? index : nil)
            guard let outsideLeg, legs.indices.contains(outsideLeg) else {
                waypoints[index].coordinate = path.waypoints[offset]
                continue
            }
            // Already on the network for its other Leg: kept, within the API's 30 m tolerance.
            guard legs[outsideLeg].path == nil else { continue }
            waypoints[index].coordinate = path.waypoints[offset]
            legs[outsideLeg].version += 1
            if legs[outsideLeg].mode == .follow {
                followUps.append(makeRequest(forLegsIn: outsideLeg ... outsideLeg))
            }
        }
        return .applied(followUps: followUps)
    }

    /// Routing failed. No path: a single Leg falls back to `straight` with its Waypoints
    /// where they were placed, several Legs are requested again one by one to find the
    /// faulty one. Temporary failure: the Legs stay `follow` and become pending.
    mutating func fail(_ error: RoutingError, for request: LegRoutingRequest) -> RoutingResolution {
        guard let range = currentRange(of: request) else { return .stale }
        switch error {
        case .noPath where range.count == 1:
            legs[range.lowerBound].mode = .straight
            legs[range.lowerBound].path = nil
            legs[range.lowerBound].version += 1
            legs[range.lowerBound].state = .computed
            return .applied(followUps: [])
        case .noPath:
            let followUps = range.map { index in
                legs[index].version += 1
                return makeRequest(forLegsIn: index ... index)
            }
            return .applied(followUps: followUps)
        case .temporary, .rateLimited:
            for index in range {
                legs[index].state = .pending
            }
            return .applied(followUps: [])
        }
    }

    // MARK: Private

    private mutating func makeRequest(forLegsIn range: ClosedRange<Int>) -> LegRoutingRequest {
        for index in range {
            legs[index].state = .computing
        }
        return LegRoutingRequest(
            targets: range.map { LegRoutingRequest.Target(legID: legs[$0].id, version: legs[$0].version) },
            waypoints: waypoints[range.lowerBound ... range.upperBound + 1].map(\.coordinate),
            profile: sport.routingProfile
        )
    }

    /// Indices of the request's Legs if they still exist in order, at the same version,
    /// still `follow`, with the same endpoints; `nil` when the answer is stale.
    private func currentRange(of request: LegRoutingRequest) -> ClosedRange<Int>? {
        guard
            let first = request.targets.first,
            let start = legs.firstIndex(where: { $0.id == first.legID }),
            start + request.targets.count <= legs.count
        else { return nil }
        let range = start ... start + request.targets.count - 1
        for (target, index) in zip(request.targets, range) {
            let leg = legs[index]
            guard leg.id == target.legID, leg.version == target.version, leg.mode == .follow else { return nil }
        }
        guard waypoints[start ... range.upperBound + 1].map(\.coordinate) == request.waypoints else { return nil }
        return range
    }
}
