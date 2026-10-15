import Foundation

/// Progress along a followed Itinerary (ADR-031 §6), computed on the phone only from its
/// cached track: the distance from the start of the track, which never goes back. Distance
/// left = total − progress, never total − Recording distance.
///
/// - First snap: the first track point in track order within 50 m of the athlete wins (a
///   loop shows its full distance, a start halfway what is left from there).
/// - On the track: each position is projected onto a forward window only (−30 m to + the
///   distance moved since the previous position + a margin); a U-turn freezes the value.
/// - Off the track: the value freezes; re-snapping searches the whole rest of the track
///   ahead of the progress, so a shortcut lowers the distance left.
struct ItineraryProgress: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// No position within 50 m of the track yet: distance left shows "—".
        case notSnapped
        case onTrack
        /// "Hors Itinéraire": the last value is frozen.
        case offTrack
        /// "Itinéraire terminé": 0 left, nothing more happens.
        case finished
    }

    /// What is saved with the Recording (ADR-031 §10): re-snapping on resume would send a
    /// loop back to its start.
    struct Saved: Equatable, Sendable {
        /// Progress in meters along the track as the phone measures it.
        let alongM: Double
        let hasSnapped: Bool
    }

    static let snapRadiusM = 50.0
    static let windowBehindM = 30.0
    static let windowMarginM = 30.0
    /// Closer to the finish than one resampling step: the Itinerary is finished.
    static let finishToleranceM = 20.0

    let total: Distance
    private(set) var status: Status
    private let track: TrackGeometry
    /// Meters along `track`.
    private var along: Double
    private var lastPosition: Coordinate?

    /// - Parameter total: the distance the API measured, shown to the athlete.
    init(track points: [Coordinate], total: Distance, saved: Saved? = nil) {
        self.total = total
        track = TrackGeometry(points)
        along = min(max(saved?.alongM ?? 0, 0), track.length)
        status = saved?.hasSnapped == true ? .onTrack : .notSnapped
        if status == .onTrack, along >= track.length - Self.finishToleranceM {
            status = .finished
        }
    }

    var saved: Saved {
        Saved(alongM: along, hasSnapped: status != .notSnapped)
    }

    /// Share of the track done, 0 to 1.
    var fraction: Double {
        if status == .finished { return 1 }
        guard track.length > 0 else { return 0 }
        return min(1, along / track.length)
    }

    /// Distance done along the Itinerary, in the API's distance.
    var progress: Distance {
        Distance(meters: total.meters * fraction)
    }

    /// `nil` before the first snap.
    var remaining: Distance? {
        status == .notSnapped ? nil : Distance(meters: max(0, total.meters - progress.meters))
    }

    /// Follows the athlete's position, during a Pause too; inaccurate fixes are ignored.
    mutating func update(with sample: LocationSample) {
        guard status != .finished, RecordingSnapshot.isAccurate(sample), track.length > 0 else { return }
        let position = sample.coordinate
        let moved = lastPosition.map { position.distance(to: $0).meters } ?? 0
        lastPosition = position

        switch status {
        case .notSnapped:
            guard let snapped = track.firstSnap(of: position, from: 0, radius: Self.snapRadiusM) else { return }
            along = snapped
            status = .onTrack
        case .onTrack, .offTrack:
            let window = (along - Self.windowBehindM)...(along + moved + Self.windowMarginM)
            if let match = track.nearest(to: position, in: window), match.distance <= Self.snapRadiusM {
                along = max(along, match.along)
                status = .onTrack
            } else if let snapped = track.firstSnap(of: position, from: along, radius: Self.snapRadiusM) {
                along = max(along, snapped)
                status = .onTrack
            } else {
                status = .offTrack
            }
        case .finished:
            return
        }
        if along >= track.length - Self.finishToleranceM {
            status = .finished
        }
    }

    // MARK: - Return path (ADR-031 §7)

    /// Where a Return path leads.
    struct ReturnPoint: Equatable, Sendable {
        let coordinate: Coordinate
        /// Meters along the track as the phone measures it.
        let alongM: Double
    }

    /// The track point ahead of the progress closest to `position` as the crow flies; the start
    /// of the Itinerary before the first snap.
    func returnPoint(for position: Coordinate) -> ReturnPoint? {
        guard track.length > 0, let first = track.points.first else { return nil }
        guard status != .notSnapped else { return ReturnPoint(coordinate: first, alongM: 0) }
        guard let match = track.nearest(to: position, in: along...track.length),
              let coordinate = track.coordinate(at: match.along)
        else { return nil }
        return ReturnPoint(coordinate: coordinate, alongM: match.along)
    }

    /// What is left of the Itinerary from `point` on, in the API's distance.
    func remaining(from point: ReturnPoint) -> Distance {
        guard track.length > 0 else { return total }
        return Distance(meters: max(0, total.meters * (1 - min(1, max(0, point.alongM) / track.length))))
    }
}
