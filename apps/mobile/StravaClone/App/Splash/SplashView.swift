import SwiftUI

/// The "dive into the N" splash (ADR-032 §4), laid over `RootView` on a cold launch. Its first
/// frame is the launch screen's plain orange; the white N draws itself, pulses while the
/// session is unknown, then becomes a window cut out of the orange layer that grows until the
/// app shows through. Timing lives in `SplashTimeline`, on the clock of the frames shown
/// (`SplashClock`).
struct SplashView: View {
    /// UI tests launch with this argument to skip the splash.
    static let disablingArgument = "-uiTestDisableSplash"

    /// Whether `AuthStore` has left `checkingSession`.
    let isSessionKnown: Bool
    /// Called once the app is fully revealed: remove the splash.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SplashClock()
    /// Splash time at which the session became known.
    @State private var sessionReadyAt: TimeInterval?

    private var timeline: SplashTimeline { SplashTimeline(reduceMotion: reduceMotion) }
    private var now: TimeInterval { clock.elapsed.seconds }
    private var isOver: Bool { timeline.end(sessionReadyAt: sessionReadyAt).map { now >= $0 } ?? false }

    var body: some View {
        let frame = timeline.frame(at: now, sessionReadyAt: sessionReadyAt)
        Canvas { canvas, size in
            Self.draw(frame, in: canvas, size: size)
        }
        .ignoresSafeArea()
        // Swallows taps until the splash is gone; nothing to read out (no wordmark, no sound).
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .onAppear { clock.start() }
        .onDisappear { clock.stop() }
        .onChange(of: isSessionKnown, initial: true) { _, isKnown in
            guard isKnown, sessionReadyAt == nil else { return }
            sessionReadyAt = now
        }
        .onChange(of: isOver) { _, isOver in
            guard isOver else { return }
            clock.stop()
            onFinished()
        }
    }
}

private extension SplashView {
    /// The launch screen's own colour, so the hand-off from it does not flash (ADR-032 §4).
    static let orange = Color("LaunchBackground")
    /// Reference layout: the N's 100 box at scale 1.7 on a 320 pt wide screen.
    static let markScaleOnReferenceWidth: CGFloat = 1.7
    static let referenceWidth: CGFloat = 320
    /// The point of the N kept at the screen's centre while it scales: the middle of the stroke
    /// between the two inner corners, (44, 50)–(51, 42), so the growing window always covers
    /// the centre and ends up covering the whole screen.
    static let anchor = CGPoint(x: 47.5, y: 46)
    static let masterPath = NervoMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))

    static func draw(_ frame: SplashFrame, in context: GraphicsContext, size: CGSize) {
        var context = context
        context.opacity = frame.layerOpacity
        context.drawLayer { layer in
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(orange))
            if let holeScale = frame.holeScale {
                layer.blendMode = .destinationOut
                stroke(masterPath, scale: holeScale, in: &layer, size: size)
                layer.blendMode = .normal
            }
            if frame.markOpacity > 0, frame.drawProgress > 0 {
                layer.opacity = frame.markOpacity
                stroke(masterPath.trimmedPath(from: 0, to: frame.drawProgress), scale: frame.markScale, in: &layer, size: size)
            }
        }
    }

    /// Strokes a path drawn in the N's 100 box, `scale` times its resting size, in white
    /// (or erasing, under `.destinationOut`).
    static func stroke(_ path: Path, scale: Double, in context: inout GraphicsContext, size: CGSize) {
        let pointsPerUnit = size.width * markScaleOnReferenceWidth / referenceWidth * scale
        let placement = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: pointsPerUnit, y: pointsPerUnit)
            .translatedBy(x: -anchor.x, y: -anchor.y)
        context.stroke(
            path.applying(placement),
            with: .color(.white),
            style: NervoMark.strokeStyle(forSide: 100 * pointsPerUnit)
        )
    }
}

#Preview {
    ZStack {
        Text("L'app").font(.largeTitle)
        SplashView(isSessionKnown: true) {}
    }
}
