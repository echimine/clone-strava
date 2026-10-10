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
    /// Waiting for its path: a routing request is in flight, or will be sent when the
    /// Waypoint being dragged rests or is released.
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
    /// Most Waypoints an Itinerary can have, the API's limit (ADR-030 §2).
    static let maxWaypoints = 200
    /// Most Legs in one routing request: Directions takes up to 25 points.
    static let maxLegsPerRequest = 24

    private(set) var sport: ItinerarySport
    private(set) var waypoints: [Waypoint] = []
    /// Always `waypoints.count - 1` Legs once there is a start.
    private(set) var legs: [Leg] = []

    init(sport: ItinerarySport) {
        self.sport = sport
    }

    /// The Waypoint cap is reached: no Waypoint can be added or inserted.
    var isFull: Bool {
        waypoints.count >= Self.maxWaypoints
    }

    /// A `follow` Leg waits for routing to be available again.
    var hasPendingLegs: Bool {
        legs.contains { $0.state == .pending }
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
    /// new finish, joined by a `follow` Leg to compute. Nothing happens once the draft is full.
    mutating func appendWaypoint(at coordinate: Coordinate) -> LegRoutingRequest? {
        guard !isFull else { return nil }
        waypoints.append(Waypoint(id: WaypointID(), coordinate: coordinate))
        guard waypoints.count >= 2 else { return nil }
        legs.append(Leg(id: LegID(), mode: .follow, path: nil, version: 0, state: .computing))
        return makeRequest(forLegsIn: legs.count - 1 ... legs.count - 1)
    }

    /// Switches a Leg between following the network and a straight line. Only that Leg
    /// changes: back to `follow`, it is the only one requested.
    mutating func setMode(_ mode: LegMode, ofLeg id: LegID) -> LegRoutingRequest? {
        guard let index = legs.firstIndex(where: { $0.id == id }), legs[index].mode != mode else { return nil }
        legs[index].mode = mode
        invalidateLeg(at: index)
        return mode == .follow ? makeRequest(forLegsIn: index ... index) : nil
    }

    /// "Supprimer" in a Waypoint's bubble. Removing the start or the finish drops its Leg;
    /// an intermediate Waypoint's neighbors are joined by one new Leg, which follows the
    /// network unless both removed Legs were straight.
    mutating func removeWaypoint(_ id: WaypointID) -> LegRoutingRequest? {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return nil }
        waypoints.remove(at: index)
        guard !legs.isEmpty else { return nil }
        if index == 0 {
            legs.removeFirst()
            return nil
        }
        if index == waypoints.count {
            legs.removeLast()
            return nil
        }
        let joined = index - 1
        let removed = legs.remove(at: index)
        if removed.mode == .follow {
            legs[joined].mode = .follow
        }
        invalidateLeg(at: joined)
        return legs[joined].mode == .follow ? makeRequest(forLegsIn: joined ... joined) : nil
    }

    /// Pulling a Leg: a Waypoint is inserted where it was pulled, splitting the Leg in two
    /// Legs of the same mode, drawn straight until requested. Nothing happens once the draft is full.
    mutating func insertWaypoint(intoLeg id: LegID, at coordinate: Coordinate) -> WaypointID? {
        guard !isFull, let index = legs.firstIndex(where: { $0.id == id }) else { return nil }
        let waypoint = Waypoint(id: WaypointID(), coordinate: coordinate)
        waypoints.insert(waypoint, at: index + 1)
        legs.insert(Leg(id: LegID(), mode: legs[index].mode, path: nil, version: 0, state: .computed), at: index + 1)
        invalidateLeg(at: index)
        invalidateLeg(at: index + 1)
        return waypoint.id
    }

    /// The finger drags a Waypoint: its Legs are drawn straight to it until requested again.
    mutating func moveWaypoint(_ id: WaypointID, to coordinate: Coordinate) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }), waypoints[index].coordinate != coordinate else {
            return
        }
        waypoints[index].coordinate = coordinate
        for leg in adjacentLegs(ofWaypointAt: index) {
            invalidateLeg(at: leg)
        }
    }

    /// One request for the `follow` Legs on either side of a Waypoint (3 points when both
    /// follow), or `nil` when both are straight.
    mutating func routeLegs(around id: WaypointID) -> LegRoutingRequest? {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return nil }
        let following = adjacentLegs(ofWaypointAt: index).filter { legs[$0].mode == .follow }
        guard let first = following.first, let last = following.last else { return nil }
        return makeRequest(forLegsIn: first ... last)
    }

    /// Whether the Legs a request covers are unchanged since it was made.
    func isCurrent(_ request: LegRoutingRequest) -> Bool {
        currentRange(of: request) != nil
    }

    /// One request per `follow` Leg still waiting for its path, e.g. in a state brought back
    /// by undo or redo after its answer was dropped.
    func requestsForComputingLegs() -> [LegRoutingRequest] {
        legs.indices
            .filter { legs[$0].mode == .follow && legs[$0].state == .computing }
            .map { request(forLegsIn: $0 ... $0) }
    }

    /// Pending Legs are requested again: each run of consecutive ones in one request, split
    /// to fit the router's limit. They are computing until answered.
    mutating func retryPendingLegs() -> [LegRoutingRequest] {
        var runs: [ClosedRange<Int>] = []
        for index in legs.indices where legs[index].state == .pending {
            if let last = runs.last, last.upperBound == index - 1, last.count < Self.maxLegsPerRequest {
                runs[runs.count - 1] = last.lowerBound ... index
            } else {
                runs.append(index ... index)
            }
        }
        return runs.map { makeRequest(forLegsIn: $0) }
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

    /// Indices of the Legs ending or starting at a Waypoint, in order.
    private func adjacentLegs(ofWaypointAt index: Int) -> [Int] {
        [index - 1, index].filter(legs.indices.contains)
    }

    /// The Leg's endpoints or mode changed: its path is dropped and older answers become stale.
    private mutating func invalidateLeg(at index: Int) {
        legs[index].path = nil
        legs[index].version += 1
        legs[index].state = legs[index].mode == .follow ? .computing : .computed
    }

    private mutating func makeRequest(forLegsIn range: ClosedRange<Int>) -> LegRoutingRequest {
        for index in range {
            legs[index].state = .computing
        }
        return request(forLegsIn: range)
    }

    private func request(forLegsIn range: ClosedRange<Int>) -> LegRoutingRequest {
        LegRoutingRequest(
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
