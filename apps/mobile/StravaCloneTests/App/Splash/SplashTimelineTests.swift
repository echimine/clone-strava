import Foundation
import Testing
@testable import StravaClone

/// The "dive into the N" splash timing (ADR-032 §4), checked against the approved reference
/// (Splash board, variant 1): a 0.3 s plain orange hold, the N drawn in 0.6 s (cubic ease-out),
/// a 0.1 s settle, then a 0.55 s reveal where the N-shaped window grows up to 71× (cubic
/// ease-in) and the orange layer fades over its last 40 %.
struct SplashTimelineTests {
    private let timeline = SplashTimeline(reduceMotion: false)

    private func expectClose(_ value: Double?, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(value.map { abs($0 - expected) < 1e-9 } == true, "\(String(describing: value)) ≠ \(expected)", sourceLocation: sourceLocation)
    }

    /// ADR-032 §4: the first frame is the launch screen, plain orange, so nothing flashes.
    @Test func theFirstFrameIsThePlainOrangeOfTheLaunchScreen() {
        let first = timeline.frame(at: 0, sessionReadyAt: nil)
        #expect(first.layerOpacity == 1)
        #expect(first.markOpacity == 0)
        #expect(first.holeScale == nil)
    }

    /// ADR-032 §4: a session known before the N is drawn does not cut the draw short; the
    /// reveal follows the draw.
    @Test func aSessionReadyBeforeTheDrawEndsIsRevealedRightAfterTheDraw() {
        expectClose(timeline.revealStart(sessionReadyAt: 0.2), 1.0)
        expectClose(timeline.end(sessionReadyAt: 0.2), 1.55)

        // Halfway through the draw: 1 − 0.5³.
        let drawing = timeline.frame(at: 0.6, sessionReadyAt: 0.2)
        expectClose(drawing.drawProgress, 0.875)
        #expect(drawing.markOpacity == 1)
        #expect(drawing.layerOpacity == 1)
        #expect(drawing.holeScale == nil)

        // Halfway through the reveal: the window is 1 + 70 × 0.5³ the N, the layer still opaque.
        let opening = timeline.frame(at: 1.275, sessionReadyAt: 0.2)
        #expect(opening.markOpacity == 0)
        expectClose(opening.holeScale, 9.75)
        expectClose(opening.layerOpacity, 1)

        // 80 % through the reveal: halfway through the fade.
        expectClose(timeline.frame(at: 1.44, sessionReadyAt: 0.2).layerOpacity, 0.5)
        expectClose(timeline.frame(at: 1.55, sessionReadyAt: 0.2).layerOpacity, 0)
    }

    /// ADR-032 §4: while the session is unknown after the draw, the N pulses gently (±4.5 % at
    /// 1.2 Hz) and the app stays hidden, however long it takes.
    @Test func aSlowSessionKeepsTheNPulsingAndTheAppHidden() {
        #expect(timeline.revealStart(sessionReadyAt: nil) == nil)
        #expect(timeline.end(sessionReadyAt: nil) == nil)

        // A quarter period (1 / 4.8 s) after the draw ends at 0.9 s: the top of the pulse.
        let top = timeline.frame(at: 0.9 + 1 / 4.8, sessionReadyAt: nil)
        expectClose(top.drawProgress, 1)
        expectClose(top.markScale, 1.045)
        // Three quarters of a period: the bottom of it.
        expectClose(timeline.frame(at: 0.9 + 3 / 4.8, sessionReadyAt: nil).markScale, 0.955)

        let muchLater = timeline.frame(at: 30, sessionReadyAt: nil)
        #expect(muchLater.layerOpacity == 1)
        #expect(muchLater.holeScale == nil)
        #expect(muchLater.markOpacity == 1)
    }

    /// ADR-032 §4: once a slow session is known, the reveal starts at once, from the size the
    /// pulsing N had at that instant, so the N does not jump.
    @Test func aSlowSessionIsRevealedWhenItBecomesKnown() {
        expectClose(timeline.revealStart(sessionReadyAt: 2.6), 2.6)
        expectClose(timeline.end(sessionReadyAt: 2.6), 3.15)

        #expect(timeline.frame(at: 2.59, sessionReadyAt: 2.6).holeScale == nil)
        let before = timeline.frame(at: 2.6, sessionReadyAt: 2.6)
        let after = timeline.frame(at: 2.6 + 1e-9, sessionReadyAt: 2.6)
        #expect(before.markScale != 1)
        #expect(after.holeScale.map { abs($0 - before.markScale) < 1e-6 } == true)
        expectClose(timeline.frame(at: 3.15, sessionReadyAt: 2.6).layerOpacity, 0)
    }

    /// ADR-032 §4, Reduce Motion: the N is there from the first frame, never drawn, pulsed nor
    /// grown, and the splash leaves with a plain 0.3 s fade as soon as the session is known,
    /// without waiting for the draw it does not play.
    @Test func withReduceMotionTheNAppearsAtOnceAndTheSplashFadesOnceTheSessionIsKnown() {
        let reduced = SplashTimeline(reduceMotion: true)
        let first = reduced.frame(at: 0, sessionReadyAt: nil)
        #expect(first.markOpacity == 1)
        #expect(first.drawProgress == 1)
        #expect(first.layerOpacity == 1)

        let waiting = reduced.frame(at: 0.9 + 1 / 4.8, sessionReadyAt: nil)
        #expect(waiting.markScale == 1)
        #expect(waiting.layerOpacity == 1)

        // A session known right away: the fade starts at once.
        expectClose(reduced.revealStart(sessionReadyAt: 0.05), 0.05)
        expectClose(reduced.end(sessionReadyAt: 0.05), 0.35)
        expectClose(reduced.frame(at: 0.2, sessionReadyAt: 0.05).layerOpacity, 0.5)

        // A slow session: the fade starts when it is known.
        expectClose(reduced.revealStart(sessionReadyAt: 2), 2)
        expectClose(reduced.end(sessionReadyAt: 2), 2.3)
        let fading = reduced.frame(at: 2.15, sessionReadyAt: 2)
        #expect(fading.holeScale == nil)
        #expect(fading.markOpacity == 1)
        #expect(fading.markScale == 1)
        expectClose(fading.layerOpacity, 0.5)
        expectClose(reduced.frame(at: 2.3, sessionReadyAt: 2).layerOpacity, 0)
    }
}
