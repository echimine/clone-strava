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
}

/// The track as segments with their cumulative distance, and projections onto it.
private struct TrackGeometry: Equatable, Sendable {
    let points: [Coordinate]
    /// Distance from the start to each point.
    let cumulative: [Double]

    init(_ points: [Coordinate]) {
        self.points = points
        var cumulative = [0.0]
        for (from, to) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + from.distance(to: to).meters)
        }
        self.cumulative = cumulative
    }

    var length: Double { cumulative.last ?? 0 }

    private var segmentCount: Int { max(0, points.count - 1) }

    /// The closest point of the track between `range` bounds, then further ahead while it
    /// keeps getting closer (a window never cuts a projection short). Ties go to the earliest.
    func nearest(to position: Coordinate, in range: ClosedRange<Double>) -> (along: Double, distance: Double)? {
        var best: (along: Double, distance: Double, segment: Int)?
        for segment in 0..<segmentCount where cumulative[segment + 1] >= range.lowerBound && cumulative[segment] <= range.upperBound {
            let match = project(position, on: segment, within: range)
            if best == nil || match.distance < best!.distance {
                best = (match.along, match.distance, segment)
            }
        }
        guard let found = best else { return nil }
        return descend(from: found, toward: position)
    }

    /// The first segment in track order, from `along` on, with a point within `radius`, then
    /// the closest point from there on while it keeps getting closer.
    func firstSnap(of position: Coordinate, from along: Double, radius: Double) -> Double? {
        let range = along...length
        for segment in 0..<segmentCount where cumulative[segment + 1] >= along {
            let match = project(position, on: segment, within: range)
            if match.distance <= radius {
                return descend(from: (match.along, match.distance, segment), toward: position).along
            }
        }
        return nil
    }

    private func descend(
        from start: (along: Double, distance: Double, segment: Int),
        toward position: Coordinate
    ) -> (along: Double, distance: Double) {
        var best = start
        var segment = start.segment
        while true {
            let range = best.along...length
            var improved = false
            // The rest of the current segment, then the next ones.
            let current = project(position, on: segment, within: range)
            if current.distance < best.distance - 0.01 {
                best = (current.along, current.distance, segment)
                improved = true
            }
            guard segment + 1 < segmentCount else { break }
            let next = project(position, on: segment + 1, within: range)
            if next.distance < best.distance - 0.01 {
                best = (next.along, next.distance, segment + 1)
                segment += 1
                continue
            }
            if !improved { break }
        }
        return (best.along, best.distance)
    }

    /// The closest point of one segment to `position`, kept between `range` bounds.
    private func project(_ position: Coordinate, on segment: Int, within range: ClosedRange<Double>) -> (along: Double, distance: Double) {
        let from = points[segment]
        let to = points[segment + 1]
        let start = cumulative[segment]
        let length = cumulative[segment + 1] - start
        // Local plane in meters around the segment start: fine for ~20 m segments.
        let metersPerDegreeLat = 111_195.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(from.latitude * .pi / 180)
        let bx = (to.longitude - from.longitude) * metersPerDegreeLon
        let by = (to.latitude - from.latitude) * metersPerDegreeLat
        let px = (position.longitude - from.longitude) * metersPerDegreeLon
        let py = (position.latitude - from.latitude) * metersPerDegreeLat
        let squared = bx * bx + by * by
        var t = squared > 0 ? (px * bx + py * by) / squared : 0
        t = min(max(t, 0), 1)
        if length > 0 {
            let lower = (range.lowerBound - start) / length
            let upper = (range.upperBound - start) / length
            t = min(max(t, max(0, lower)), min(1, max(upper, 0)))
        }
        let dx = px - bx * t
        let dy = py - by * t
        return (start + length * t, (dx * dx + dy * dy).squareRoot())
    }
}
