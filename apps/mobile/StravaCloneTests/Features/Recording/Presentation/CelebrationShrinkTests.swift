import SwiftUI
import Testing
@testable import StravaClone

/// ADR-032 §5, step 5: the celebration's map shrinks into the mini-map without a jump. Its
/// framing and its line move with the shrink, frame by frame, from the full-screen look to the
/// mini-map's.
struct CelebrationShrinkTests {
    private let fullHeight = 874.0

    @Test func fullScreenTheMapKeepsTheCelebrationsLook() {
        let shrink = CelebrationShrink(height: fullHeight, fullHeight: fullHeight)

        #expect(shrink.progress == 0)
        #expect(shrink.lineWidth == 6)
        #expect(shrink.endpointsOpacity == 0)
        // Room above the trace and, larger, below it for the stats.
        expectClose(shrink.overviewPadding, EdgeInsets(top: 104.88, leading: 32, bottom: 209.76, trailing: 32))
    }

    /// At the mini-map's size, the map looks like the mini-map it hands over to: its 4 pt line,
    /// its start and finish markers, its framing.
    @Test func atTheMiniMapsSizeTheMapLooksLikeTheMiniMap() {
        let shrink = CelebrationShrink(height: 200, fullHeight: fullHeight)

        #expect(shrink.progress == 1)
        #expect(shrink.lineWidth == 4)
        #expect(shrink.endpointsOpacity == 1)
        #expect(shrink.overviewPadding == RecordingTraceMap.overviewPadding)
    }

    /// Halfway down, halfway there: no threshold where the framing switches at once.
    @Test func halfwayTheLookIsHalfway() {
        let shrink = CelebrationShrink(height: 537, fullHeight: fullHeight)

        #expect(shrink.progress == 0.5)
        #expect(shrink.lineWidth == 5)
        expectClose(shrink.overviewPadding, EdgeInsets(top: 68.44, leading: 28, bottom: 120.88, trailing: 28))
    }

    /// Before its first layout, the map has no size: it is not shrinking.
    @Test func withoutASizeTheMapIsNotShrinking() {
        #expect(CelebrationShrink(height: 0, fullHeight: 0).progress == 0)
    }

    private func expectClose(_ actual: EdgeInsets, _ expected: EdgeInsets, sourceLocation: SourceLocation = #_sourceLocation) {
        for (a, e) in [(actual.top, expected.top), (actual.leading, expected.leading), (actual.bottom, expected.bottom), (actual.trailing, expected.trailing)] {
            #expect(abs(a - e) < 1e-9, sourceLocation: sourceLocation)
        }
    }
}
