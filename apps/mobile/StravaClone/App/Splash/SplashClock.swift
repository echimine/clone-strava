import Foundation
import Observation
import QuartzCore

/// The time the splash has been on screen (ADR-032 §4), counted from the frames actually shown.
/// The main thread is busiest right at launch: a stalled frame advances the splash by one
/// thirtieth of a second at most, so the N's draw pauses instead of being skipped.
struct SplashElapsedTime {
    static let longestStep: TimeInterval = 1.0 / 30

    private(set) var seconds: TimeInterval = 0
    private var lastFrame: TimeInterval?

    /// A frame is shown at `timestamp` (seconds, any monotonic origin).
    mutating func advance(to timestamp: TimeInterval) {
        if let lastFrame {
            seconds += min(max(timestamp - lastFrame, 0), Self.longestStep)
        }
        lastFrame = timestamp
    }
}

/// Drives `SplashElapsedTime` from the display's refresh, while the splash is shown.
@Observable
@MainActor
final class SplashClock {
    private(set) var elapsed = SplashElapsedTime()
    @ObservationIgnored private var displayLink: CADisplayLink?

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(clock: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick(_ timestamp: CFTimeInterval) {
        elapsed.advance(to: timestamp)
    }
}

/// `CADisplayLink` retains its target: this one holds the clock weakly, so the clock can go
/// away with the splash.
@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var clock: SplashClock?

    init(clock: SplashClock) {
        self.clock = clock
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let clock else {
            link.invalidate()
            return
        }
        clock.tick(link.timestamp)
    }
}
