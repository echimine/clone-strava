import Foundation
import Testing
@testable import StravaClone

/// The running rule (ADR-031 §4): smoothed Core Motion, GPS as a back-up for the resume.
struct AutoPauseMotionRuleTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func standingStillFiveSecondsPausesAndRunningAgainResumes() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        trace.motion(.stationary)
        trace.stand(seconds: 10)
        trace.motion(.running)
        trace.move(seconds: 10, speed: 3)

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start) == [
            .pause(at: at(35), position: trace.coordinate(at: at(30))),
            .resume(at: at(40)),
        ])
    }

    @Test func walkingNeverPauses() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        for _ in 0..<20 {
            trace.motion(.walking)
            trace.move(seconds: 2, speed: 1.3, reportedSpeed: .some(nil))
            trace.motion(.stationary, confidence: .low)
            trace.move(seconds: 2, speed: 1.3, reportedSpeed: .some(nil))
        }

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start).isEmpty)
    }

    @Test func lowConfidenceStationaryReadingsAreIgnored() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        trace.motion(.stationary, confidence: .low)
        trace.stand(seconds: 20)

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start).isEmpty)
    }

    @Test func stationaryOnlyThreeSecondsOutOfFiveDoesNotPause() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        for _ in 0..<5 {
            trace.motion(.stationary)
            trace.stand(seconds: 3)
            trace.motion(.walking)
            trace.stand(seconds: 2)
        }

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start).isEmpty)
    }

    @Test func aGPSSpeedOfTwoMetresPerSecondPreventsThePause() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        trace.motion(.stationary, confidence: .medium)
        trace.move(seconds: 20, speed: 2.5)

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start).isEmpty)
    }

    @Test func threeSecondsOfWalkingResumeFromTheStartOfTheWalk() {
        var trace = SyntheticTrace(start: start)
        trace.motion(.running)
        trace.move(seconds: 30, speed: 3)
        trace.motion(.stationary)
        trace.stand(seconds: 20)
        trace.motion(.walking)
        trace.move(seconds: 2, speed: 1.3)
        trace.motion(.stationary, confidence: .low)
        trace.move(seconds: 2, speed: 1.3)

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start).last == .resume(at: at(50)))
    }

    @Test func withoutCoreMotionTheGPSRuleResumes() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 3)
        trace.stand(seconds: 3)
        trace.stationary()
        trace.stand(seconds: 20)
        let departure = trace.now
        trace.move(seconds: 10, speed: 3)

        #expect(AutoPauseReplay.run(trace.signals, rule: .motion, since: start) == [
            .pause(at: at(33), position: trace.coordinate(at: at(30))),
            .resume(at: departure),
        ])
    }

    @Test func theMeasuredWalkNeverPausesWhileWalking() throws {
        let walk = try MeasuredWalk.load()
        let since = try #require(walk.signals.first?.date)
        #expect(walk.signals.count == 262) // 209 fixes, 53 Core Motion readings

        for rule in [AutoPauseRule.motion] {
            let pauses = AutoPauseReplay.run(walk.signals, rule: rule, since: since).compactMap(\.pauseDate)
            for pause in pauses {
                #expect(walk.isStopped(at: pause), "\(rule) paused at \(pause.timeIntervalSince(since)) s while walking")
            }
        }
    }
}

extension AutoPauseDecision {
    var pauseDate: Date? {
        if case let .pause(at, _) = self { at } else { nil }
    }
}
