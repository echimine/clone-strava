import Foundation

/// The live stats of a Recording at one instant (ADR-031 §5). No elevation gain live.
struct RecordingStats: Equatable, Sendable {
    /// Under this timer, the average pace is not meaningful yet.
    static let paceWarmUp = Duration.seconds(30)
    /// Slower than 59:59 /km, the average pace shows nothing.
    static let slowestPace = Duration.seconds(3_599)

    let sport: RecordingSport
    /// The timer: time since Start minus Pauses.
    let elapsed: Duration
    let distance: Distance
    /// `nil` during a Pause.
    let currentSpeedMs: Double?

    private var elapsedSeconds: Double {
        Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Timer / distance, `nil` for the first 30 s, without distance or beyond 59:59 /km.
    var averagePace: Duration? {
        guard elapsed >= Self.paceWarmUp, distance.meters > 0 else { return nil }
        let pace = Duration.milliseconds(Int64((elapsedSeconds / distance.kilometers * 1_000).rounded()))
        return pace <= Self.slowestPace ? pace : nil
    }

    var averageSpeedMs: Double {
        elapsedSeconds > 0 ? distance.meters / elapsedSeconds : 0
    }
}

/// Current speed (ADR-031 §5): GPS distance over the last ~5 s divided by that time, never
/// `CLLocation.speed`. The window restarts on Resume.
struct CurrentSpeed: Sendable {
    static let window: TimeInterval = 5

    private var movingSince: Date
    private var legs: [(end: Date, distance: Distance)] = []

    init(movingSince: Date) {
        self.movingSince = movingSince
    }

    mutating func record(_ leg: Distance, at date: Date) {
        legs.append((date, leg))
        legs.removeAll { $0.end <= date.addingTimeInterval(-Self.window) }
    }

    mutating func reset(movingSince date: Date) {
        movingSince = date
        legs.removeAll()
    }

    /// `nil` until some time has passed since Start or Resume.
    func speedMs(at now: Date) -> Double? {
        let span = min(Self.window, now.timeIntervalSince(movingSince))
        guard span > 0 else { return nil }
        let windowStart = now.addingTimeInterval(-Self.window)
        let meters = legs.filter { $0.end > windowStart && $0.end <= now }.reduce(0) { $0 + $1.distance.meters }
        return meters / span
    }
}
