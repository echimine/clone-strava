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
    /// a `straight` Leg, or a `follow` Leg not computed yet. A `follow` Leg recomputed for a
    /// sport of another category keeps its former path, drawn provisional, until answered.
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
    /// A batch of a sport category change whose first Waypoint is the junction with the
    /// previous batch: that batch snaps it.
    var joinsPreviousBatch = false
    /// A batch of a sport category change whose last Waypoint is the junction with the next
    /// batch: this batch snaps it.
    var joinsNextBatch = false

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

    /// A draft as given, e.g. a saved Itinerary reopened (`init(restoring:)`).
    init(sport: ItinerarySport, waypoints: [Waypoint], legs: [Leg]) {
        self.sport = sport
        self.waypoints = waypoints
        self.legs = legs
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

    /// Requests for the `follow` Legs waiting for their path that neither `awaited` nor
    /// `excluded` covers: in a state brought back by undo or redo after their answer was
    /// dropped, or once a gesture overtook their batch. Runs of consecutive ones are split
    /// into batches like a sport change; a run next to an awaited batch shares its junction.
    func requestsForStrandedLegs(awaited: [LegRoutingRequest], excluding excluded: Set<LegID>) -> [LegRoutingRequest] {
        let covered = awaited.reduce(into: excluded) { $0.formUnion($1.legIDs) }
        let stranded = runs { legs[$0].mode == .follow && legs[$0].state == .computing && !covered.contains(legs[$0].id) }
        return stranded.flatMap { run in
            var requests = batchRequests(forLegsIn: run)
            if run.lowerBound > 0, awaited.contains(where: {
                $0.joinsNextBatch && $0.targets.last?.legID == legs[run.lowerBound - 1].id
            }) {
                requests[0].joinsPreviousBatch = true
            }
            if run.upperBound < legs.count - 1, awaited.contains(where: {
                $0.joinsPreviousBatch && $0.targets.first?.legID == legs[run.upperBound + 1].id
            }) {
                requests[requests.count - 1].joinsNextBatch = true
            }
            return requests
        }
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

    /// The athlete picks another sport. Within the same category the paths stay as they are;
    /// in another one, each run of consecutive `follow` Legs is requested again in batches of
    /// at most 25 points, sharing their junction Waypoint. The Legs keep their former path
    /// until answered, and `straight` Legs are not touched.
    mutating func changeSport(to newSport: ItinerarySport) -> [LegRoutingRequest] {
        let previousCategory = sport.category
        sport = newSport
        guard newSport.category != previousCategory else { return [] }
        return runs { legs[$0].mode == .follow }.flatMap { run in
            for index in run {
                legs[index].version += 1
                legs[index].state = .computing
            }
            return batchRequests(forLegsIn: run)
        }
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
            // A junction between batches of a sport change takes the position the first one snapped.
            if offset == 0, request.joinsPreviousBatch {
                continue
            }
            if index == waypointRange.upperBound, request.joinsNextBatch {
                moveJunction(at: index, to: path.waypoints[offset])
                continue
            }
            let outsideLeg = index == range.lowerBound ? index - 1 : (index == waypointRange.upperBound ? index : nil)
            guard let outsideLeg, legs.indices.contains(outsideLeg) else {
                waypoints[index].coordinate = path.waypoints[offset]
                continue
            }
            // Already on the network for its other Leg: kept, within the API's 30 m tolerance.
            // A Leg recomputed for a new sport keeps its former path but is not routed yet.
            guard legs[outsideLeg].path == nil || legs[outsideLeg].state != .computed else { continue }
            waypoints[index].coordinate = path.waypoints[offset]
            legs[outsideLeg].version += 1
            if legs[outsideLeg].mode == .follow {
                followUps.append(makeRequest(forLegsIn: outsideLeg ... outsideLeg))
            }
        }
        if request.joinsPreviousBatch {
            connectStart(ofLegAt: range.lowerBound)
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
                var followUp = makeRequest(forLegsIn: index ... index)
                followUp.joinsPreviousBatch = request.joinsPreviousBatch && index == range.lowerBound
                followUp.joinsNextBatch = request.joinsNextBatch && index == range.upperBound
                return followUp
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

    /// Index ranges of the runs of consecutive Legs matching `isIncluded`.
    private func runs(where isIncluded: (Int) -> Bool) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for index in legs.indices where isIncluded(index) {
            if let last = runs.last, last.upperBound == index - 1 {
                runs[runs.count - 1] = last.lowerBound ... index
            } else {
                runs.append(index ... index)
            }
        }
        return runs
    }

    /// Requests for a run of Legs in batches of at most 25 points, sent in parallel:
    /// neighboring batches share their junction Waypoint, snapped by the first one.
    private func batchRequests(forLegsIn run: ClosedRange<Int>) -> [LegRoutingRequest] {
        let starts = Array(stride(from: run.lowerBound, through: run.upperBound, by: Self.maxLegsPerRequest))
        return starts.enumerated().map { offset, start in
            var request = request(forLegsIn: start ... min(start + Self.maxLegsPerRequest - 1, run.upperBound))
            request.joinsPreviousBatch = offset > 0
            request.joinsNextBatch = offset < starts.count - 1
            return request
        }
    }

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
        let endpoints = waypoints[start ... range.upperBound + 1].map(\.coordinate)
        // The previous batch of a sport change may have snapped the junction since.
        guard endpoints.dropFirst() == request.waypoints.dropFirst(),
              request.joinsPreviousBatch || endpoints.first == request.waypoints.first
        else { return nil }
        return range
    }

    /// The batch before a junction snapped it there: the next Leg, if it has a path, starts
    /// at the new position.
    private mutating func moveJunction(at index: Int, to coordinate: Coordinate) {
        let former = waypoints[index].coordinate
        waypoints[index].coordinate = coordinate
        guard legs.indices.contains(index), var next = legs[index].path else { return }
        if next.first == former {
            next[0] = coordinate
            if next.count > 2, next[1] == coordinate {
                next.removeFirst()
            }
            legs[index].path = next
        }
        connectStart(ofLegAt: index)
    }

    /// A batch snapped its junction elsewhere than the previous batch: a connector joins the
    /// junction to the start of its path, a few meters within the API's 30 m tolerance.
    private mutating func connectStart(ofLegAt index: Int) {
        let junction = waypoints[index].coordinate
        guard var path = legs[index].path, let start = path.first, start != junction else { return }
        path.insert(junction, at: 0)
        legs[index].path = path
    }
}
