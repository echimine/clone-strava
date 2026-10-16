import Foundation

/// What the splash shows at one instant (ADR-032 §4). Scales are multiples of the N's resting
/// size; opacities are 0…1.
struct SplashFrame: Equatable {
    /// How much of the white N is drawn (`trim(from: 0, to: drawProgress)`).
    var drawProgress: Double
    /// The white N's opacity: hidden before the draw and once it has become a window.
    var markOpacity: Double
    /// The white N's scale, which pulses while the session is unknown.
    var markScale: Double
    /// The N-shaped window cut out of the orange layer, `nil` until the reveal.
    var holeScale: Double?
    /// The orange layer's opacity: 1 hides the app, 0 is the end of the splash.
    var layerOpacity: Double
}

/// Timing of the "dive into the N" splash (ADR-032 §4), from the time since the splash
/// appeared and the time the session became known (`AuthStore` left `checkingSession`).
/// Times are in seconds from the splash's first frame. Curves and durations follow the
/// approved reference (Splash board, variant 1).
struct SplashTimeline {
    /// The plain orange of the launch screen, held before the draw.
    static let launchHold: TimeInterval = 0.3
    static let drawDuration: TimeInterval = 0.6
    /// A beat between the end of the draw and the reveal.
    static let settle: TimeInterval = 0.1
    static let revealDuration: TimeInterval = 0.55
    /// The window grows up to `1 + revealGrowth` times the N.
    static let revealGrowth = 70.0
    /// The orange layer fades over the reveal's last 40 %.
    static let fadeFrom = 0.6
    /// While the session is unknown after the draw, the N pulses by ±4.5 % at 1.2 Hz.
    static let pulseAmplitude = 0.045
    static let pulseFrequency = 1.2
    /// Reduce Motion: a plain fade instead of the dive.
    static let reducedFadeDuration: TimeInterval = 0.3

    let reduceMotion: Bool

    private static var drawEnd: TimeInterval { launchHold + drawDuration }

    /// When the reveal starts: after the draw and once the session is known, whichever comes
    /// later; under Reduce Motion, which plays no draw, as soon as the session is known. `nil`
    /// while the session is unknown: the app is never revealed before its root is decided.
    func revealStart(sessionReadyAt: TimeInterval?) -> TimeInterval? {
        sessionReadyAt.map { reduceMotion ? $0 : max(Self.drawEnd + Self.settle, $0) }
    }

    /// When the splash is over and can be removed.
    func end(sessionReadyAt: TimeInterval?) -> TimeInterval? {
        revealStart(sessionReadyAt: sessionReadyAt).map { $0 + exitDuration }
    }

    func frame(at time: TimeInterval, sessionReadyAt: TimeInterval?) -> SplashFrame {
        reduceMotion ? reducedFrame(at: time, sessionReadyAt: sessionReadyAt) : diveFrame(at: time, sessionReadyAt: sessionReadyAt)
    }

    /// How long the splash takes to leave once its reveal starts: the dive, or the plain fade.
    private var exitDuration: TimeInterval { reduceMotion ? Self.reducedFadeDuration : Self.revealDuration }

    /// Reduce Motion: the N is there from the first frame, then the splash fades.
    private func reducedFrame(at time: TimeInterval, sessionReadyAt: TimeInterval?) -> SplashFrame {
        let faded = revealStart(sessionReadyAt: sessionReadyAt)
            .map { Self.progress(time, from: $0, over: Self.reducedFadeDuration) } ?? 0
        return SplashFrame(drawProgress: 1, markOpacity: 1, markScale: 1, holeScale: nil, layerOpacity: 1 - faded)
    }

    private func diveFrame(at time: TimeInterval, sessionReadyAt: TimeInterval?) -> SplashFrame {
        let drawn = Self.easeOut(Self.progress(time, from: Self.launchHold, over: Self.drawDuration))
        let start = revealStart(sessionReadyAt: sessionReadyAt)
        var frame = SplashFrame(
            drawProgress: drawn,
            markOpacity: drawn > 0 ? 1 : 0,
            // The pulse stops, and holds its size, as soon as the session is known.
            markScale: Self.pulse(at: min(time, sessionReadyAt ?? time)),
            holeScale: nil,
            layerOpacity: 1
        )
        guard let start, time > start else { return frame }
        let revealed = Self.progress(time, from: start, over: Self.revealDuration)
        frame.markOpacity = 0
        // The window opens from the size the N had when the reveal started, so it does not jump.
        frame.holeScale = frame.markScale * (1 + Self.revealGrowth * Self.easeIn(revealed))
        frame.layerOpacity = revealed < Self.fadeFrom ? 1 : 1 - (revealed - Self.fadeFrom) / (1 - Self.fadeFrom)
        return frame
    }

    /// The N's scale while it waits for the session: 1 until the draw ends, then a sine.
    private static func pulse(at time: TimeInterval) -> Double {
        guard time > drawEnd else { return 1 }
        return 1 + pulseAmplitude * sin((time - drawEnd) * 2 * .pi * pulseFrequency)
    }

    private static func progress(_ time: TimeInterval, from start: TimeInterval, over duration: TimeInterval) -> Double {
        min(max((time - start) / duration, 0), 1)
    }

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func easeIn(_ x: Double) -> Double { x * x * x }
}
