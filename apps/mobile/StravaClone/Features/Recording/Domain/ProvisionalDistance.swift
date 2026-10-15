import Foundation

/// The provisional distance of a Recording (ADR-031 §5), with the server's cleanup rules
/// (`cleanTrace` then `computeMetrics`): fixes less accurate than 50 m are dropped, as are
/// out-of-order timestamps and jumps faster than the sport's plausible top speed; the hop
/// across a Pause counts for nothing and is never a jump. Not shared with TypeScript: the
/// shared JSON test traces keep both within 1 %.
struct ProvisionalDistance: Sendable {
    /// `MAX_TRACE_ACCURACY_M` of the server.
    static let maxAccuracyM = 50.0

    let maxSpeedMs: Double
    private(set) var total = Distance.zero
    private var lastKept: LocationSample?
    private var crossesPause = false

    init(sport: RecordingSport) {
        maxSpeedMs = sport.maxPlausibleSpeedMs
    }

    /// A Pause ended since the last fix: the next hop (from one fix to the next) straddles it.
    mutating func notePause() {
        crossesPause = true
    }

    /// Adds a fix and returns the length of the hop it counted, `nil` when it counted none.
    @discardableResult
    mutating func append(_ sample: LocationSample) -> Distance? {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= Self.maxAccuracyM else { return nil }
        guard let previous = lastKept else {
            keep(sample)
            return nil
        }
        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return nil }
        let hop = previous.coordinate.distance(to: sample.coordinate)
        if crossesPause {
            keep(sample)
            return nil
        }
        guard hop.meters / elapsed <= maxSpeedMs else { return nil }
        keep(sample)
        total = total + hop
        return hop
    }

    private mutating func keep(_ sample: LocationSample) {
        lastKept = sample
        crossesPause = false
    }

    /// Replays stored points and finished Pauses (resume, finish screen, shared test traces).
    static func measure(_ samples: [LocationSample], pauses: [RecordingPause], sport: RecordingSport) -> Distance {
        replaying(samples, pauses: pauses, sport: sport).total
    }

    /// The distance after the stored points, ready for the next live fix.
    static func replaying(_ samples: [LocationSample], pauses: [RecordingPause], sport: RecordingSport) -> ProvisionalDistance {
        var distance = ProvisionalDistance(sport: sport)
        var remainingPauses = pauses.sorted { $0.start < $1.start }[...]
        for sample in samples {
            while let pause = remainingPauses.first, pause.end <= sample.timestamp {
                distance.notePause()
                remainingPauses = remainingPauses.dropFirst()
            }
            distance.append(sample)
        }
        if !remainingPauses.isEmpty {
            distance.notePause()
        }
        return distance
    }
}
