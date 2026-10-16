import Foundation
import Testing
@testable import StravaClone

/// The splash's clock (ADR-032 §4) counts the frames actually shown, so a busy main thread at
/// launch pauses the draw instead of skipping it.
struct SplashElapsedTimeTests {
    @Test func itStartsAtTheFirstFrameAndFollowsSmoothFrames() {
        var elapsed = SplashElapsedTime()
        elapsed.advance(to: 100)
        #expect(elapsed.seconds == 0)
        elapsed.advance(to: 100 + 1.0 / 60)
        elapsed.advance(to: 100 + 2.0 / 60)
        #expect(abs(elapsed.seconds - 2.0 / 60) < 1e-9)
    }

    @Test func aStalledFrameAdvancesTheSplashByOneThirtiethOfASecondAtMost() {
        var elapsed = SplashElapsedTime()
        elapsed.advance(to: 100)
        elapsed.advance(to: 100.5)
        #expect(abs(elapsed.seconds - 1.0 / 30) < 1e-9)
    }
}
