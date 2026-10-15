import Foundation

/// The Itinerary followed during a Recording (ADR-031 §2, §6, §7, §10): the copy loaded from the
/// cache at Start, kept until the end even if the Itinerary is deleted elsewhere, its progress
/// and its Return path. It can be removed, never replaced.
struct FollowedItinerary: Equatable, Sendable {
    /// What the Recording screen and the Live Activity show next to the distance left.
    enum State: Equatable, Sendable {
        /// No position within 50 m of the track yet, no Return path: "—".
        case notSnapped
        case onTrack
        /// "Hors Itinéraire": off it for 3 points and 10 s, no Return path to show.
        case offTrack
        /// "Chemin recalculé".
        case returnPath
        /// "Itinéraire terminé".
        case finished
    }

    let id: ItineraryID
    let name: String
    /// The cached track, start to finish.
    let track: [Coordinate]
    var progress: ItineraryProgress
    /// "Chemin recalculé": the way back to the track, until re-snapping.
    private(set) var returnPath: ReturnPath? {
        didSet {
            pathGeometry = returnPath.map { TrackGeometry($0.path) }
            pathDoneM = 0
        }
    }
    private(set) var rules: ReturnPathRules
    private var pathGeometry: TrackGeometry?
    /// The athlete's projection on the Return path, meters from its start.
    private var pathDoneM = 0.0

    /// - Parameter total: the distance the API measured.
    init(
        id: ItineraryID,
        name: String,
        track: [Coordinate],
        total: Distance,
        saved: ItineraryProgress.Saved? = nil,
        returnPath: ReturnPath? = nil
    ) {
        self.id = id
        self.name = name
        self.track = track
        progress = ItineraryProgress(track: track, total: total, saved: saved)
        self.returnPath = returnPath
        pathGeometry = returnPath.map { TrackGeometry($0.path) }
        rules = ReturnPathRules(isDeparted: returnPath != nil)
    }

    init(_ track: CachedItineraryTrack, name: String) {
        self.init(id: track.id, name: name, track: track.points, total: track.distance)
    }

    var state: State {
        switch progress.status {
        case .finished: .finished
        // Read back from storage, the progress is on the track until the next fix (§10); a
        // Return path is never kept on the track otherwise.
        case .onTrack: returnPath != nil ? .returnPath : .onTrack
        case .notSnapped: returnPath != nil ? .returnPath : .notSnapped
        // Off the window for less than 3 points and 10 s: the value is only frozen.
        case .offTrack: returnPath != nil ? .returnPath : rules.isDeparted ? .offTrack : .onTrack
        }
    }

    /// With a Return path, what is left of it from the athlete's projection plus what is left
    /// of the Itinerary from the return point; `nil` before the first snap without one.
    var remaining: Distance? {
        guard let returnPath, let pathGeometry, pathGeometry.length > 0 else { return progress.remaining }
        let onPath = returnPath.distance.meters * max(0, 1 - pathDoneM / pathGeometry.length)
        return Distance(meters: onPath) + progress.remaining(from: returnPath.returnPoint)
    }

    // MARK: - Return path (ADR-031 §7)

    /// Follows the athlete's position, during a Pause too. Returns what to do with the router.
    mutating func follow(_ sample: LocationSample) -> ReturnPathCommand? {
        progress.update(with: sample)
        switch progress.status {
        case .onTrack, .finished:
            return endReturnPath()
        case .notSnapped, .offTrack:
            guard RecordingSnapshot.isAccurate(sample) else { return nil }
            var isAway = true
            if let pathGeometry, let match = pathGeometry.nearest(to: sample.coordinate, in: 0...pathGeometry.length) {
                pathDoneM = match.along
                isAway = match.distance > ReturnPathRules.departureDistanceM
            }
            rules.observe(at: sample.timestamp, isAway: isAway)
            return requestIfDue(from: sample, at: sample.timestamp)
        }
    }

    /// `true` when the answer was awaited: the Return path shows, replacing the previous one.
    mutating func returnPathArrived(_ routed: RoutedReturnPath, for request: ReturnPathRequest) -> Bool {
        guard rules.arrived(for: request) else { return false }
        returnPath = ReturnPath(path: routed.path, distance: routed.distance, returnPoint: request.returnPoint)
        return true
    }

    /// `true` when the failure was awaited. No route: "Hors Itinéraire" until the next departure.
    mutating func returnPathFailed(_ error: RoutingError, for request: ReturnPathRequest, at time: Date) -> Bool {
        guard rules.failed(error, for: request, at: time) else { return false }
        if error == .noPath {
            returnPath = nil
        }
        return true
    }

    /// Back online, a Return path still wanted leaves at once. One already shown stays offline.
    mutating func connectivityChanged(_ isOnline: Bool, lastPosition: LocationSample?, at time: Date) -> ReturnPathCommand? {
        rules.connectivityChanged(isOnline)
        guard let lastPosition else { return nil }
        return requestIfDue(from: lastPosition, at: time)
    }

    /// When a wanted Return path request may leave without a new fix (retry after 30 s).
    var returnPathRetryDate: Date? { rules.nextRequestDate }

    /// The retry is due: the request leaves from the last position.
    mutating func retryReturnPath(from lastPosition: LocationSample?, at time: Date) -> ReturnPathCommand? {
        guard let lastPosition else { return nil }
        return requestIfDue(from: lastPosition, at: time)
    }

    private mutating func requestIfDue(from sample: LocationSample, at time: Date) -> ReturnPathCommand? {
        guard rules.isRequestDue(at: time), let returnPoint = progress.returnPoint(for: sample.coordinate) else {
            return nil
        }
        let bearing = sample.course.map { Bearing(degrees: $0, tolerance: 45) }
        return .send(rules.makeRequest(position: sample.coordinate, returnPoint: returnPoint, bearing: bearing, at: time))
    }

    /// Re-snapping or "Itinéraire terminé": the Return path disappears, the request is cancelled.
    private mutating func endReturnPath() -> ReturnPathCommand? {
        guard !rules.isIdle || returnPath != nil else { return nil }
        let wasAwaiting = rules.inFlight != nil
        rules.reset()
        returnPath = nil
        return wasAwaiting ? .cancel : nil
    }
}
