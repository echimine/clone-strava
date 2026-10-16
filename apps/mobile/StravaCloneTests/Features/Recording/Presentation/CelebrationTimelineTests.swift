import Foundation
import Testing
@testable import StravaClone

/// ADR-032 §5: 10 s, fixed whatever the distance. The trace draws, the stats count up,
/// a haptic at the end of the draw then at the end of the count, then the form appears.
struct CelebrationTimelineTests {
    @Test func atTheStartNothingIsDrawnNorCounted() {
        let frame = CelebrationTimeline.frame(at: 0)

        #expect(frame.traceProgress == 0)
        #expect(frame.countProgress == 0)
        #expect(frame.milestone == .drawing)
    }

    @Test func theTraceIsFullyDrawnAtTheFirstHaptic() {
        let frame = CelebrationTimeline.frame(at: CelebrationTimeline.traceDrawnAt)

        #expect(frame.traceProgress == 1)
        #expect(frame.milestone == .traceDrawn)
    }

    @Test func theCountReachesItsFinalValueAtTheSecondHaptic() {
        let before = CelebrationTimeline.frame(at: CelebrationTimeline.countedAt - 0.01)
        let frame = CelebrationTimeline.frame(at: CelebrationTimeline.countedAt)

        #expect(before.countProgress < 1)
        #expect(before.milestone == .traceDrawn)
        #expect(frame.countProgress == 1)
        #expect(frame.milestone == .counted)
    }

    /// The count eases out: fast first, slowing down on the final values (cubic: 1 − (1 − ½)³).
    @Test func halfwayThroughTheCountTheValuesAreSevenEighthsThere() {
        let middle = (CelebrationTimeline.countStartsAt + CelebrationTimeline.countedAt) / 2

        #expect(abs(CelebrationTimeline.frame(at: middle).countProgress - 0.875) < 1e-9)
    }

    /// Decided on an iPhone: 3 s went by too fast, the trace has time to be followed.
    @Test func theSequenceLastsTenSecondsThenTheFormAppears() {
        #expect(CelebrationTimeline.duration == 10)
        #expect(CelebrationTimeline.traceDrawnAt >= 6)
        #expect(CelebrationTimeline.traceDrawnAt < CelebrationTimeline.countedAt)
        #expect(CelebrationTimeline.countedAt < CelebrationTimeline.duration)

        let end = CelebrationTimeline.frame(at: CelebrationTimeline.duration + 10)
        #expect(end.traceProgress == 1)
        #expect(end.countProgress == 1)
        #expect(end.milestone == .counted)
    }
}
