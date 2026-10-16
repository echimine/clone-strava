import Foundation

/// Where the celebration stands; each step past `drawing` is punctuated by a haptic
/// (ADR-032 §5).
enum CelebrationMilestone: Int, Comparable, Sendable {
    case drawing, traceDrawn, counted

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One instant of the celebration: how much of the trace is drawn and how far the stats have
/// counted, both in 0...1.
struct CelebrationFrame: Equatable, Sendable {
    let traceProgress: Double
    let countProgress: Double
    let milestone: CelebrationMilestone
}

/// The celebration's timing (ADR-032 §5): about 3 s, fixed whatever the distance. The trace
/// draws, the stats count up from a little after the start, a haptic marks the end of each, then
/// the trace shrinks into the mini-map's place and the form appears at `duration`.
/// Pure: the background (the Mapbox map, or the no-map sketch) reads `traceProgress`.
enum CelebrationTimeline {
    static let traceDrawnAt: TimeInterval = 1.5
    static let countStartsAt: TimeInterval = 0.4
    static let countedAt: TimeInterval = 2.3
    /// The form appears; the shrink into the mini-map runs during `settleDuration` before it.
    static let duration: TimeInterval = 3.0
    static let settleDuration: TimeInterval = 0.5
    static var settlesAt: TimeInterval { duration - settleDuration }

    /// `elapsed` is the time since the celebration appeared.
    static func frame(at elapsed: TimeInterval) -> CelebrationFrame {
        let draw = fraction(elapsed, from: 0, to: traceDrawnAt)
        let count = fraction(elapsed, from: countStartsAt, to: countedAt)
        let milestone: CelebrationMilestone = count >= 1 ? .counted : draw >= 1 ? .traceDrawn : .drawing
        return CelebrationFrame(traceProgress: easeInOut(draw), countProgress: easeOut(count), milestone: milestone)
    }

    private static func fraction(_ elapsed: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        min(1, max(0, (elapsed - start) / (end - start)))
    }

    /// Cubic ease-out: the counters slow down on their final values.
    private static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// Cubic ease-in-out: the pen starts and lands gently.
    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
