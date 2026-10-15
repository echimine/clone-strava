import Foundation
import Testing
@testable import StravaClone

/// The automatic Pause rules (ADR-031 §4), replayed on timestamped synthetic traces.
struct AutoPauseDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    @Test func aRideStoppingAtATrafficLightPausesTenSecondsLaterAndResumesAtTheDeparture() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 60, speed: 8)
        let stopAt = trace.now
        trace.stand(seconds: 30)
        let departure = trace.now
        trace.move(seconds: 30, speed: 6)

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.count == 2)
        guard decisions.count == 2, case let .pause(at, position) = decisions[0],
              case let .resume(resumedAt) = decisions[1]
        else { return }
        #expect(at == stopAt.addingTimeInterval(10))
        #expect(position == trace.coordinate(at: stopAt))
        // The last point within 20 m of the Pause position before the points that move away.
        #expect(resumedAt == departure)
    }

    /// The GPS trembles at the stop, even jumping more than 20 m away (without the speed to
    /// resume), then is lost for 3 s as the athlete leaves: the departure is the last point
    /// within 20 m of the Pause position before the points that move away, not a jump.
    @Test func aGPSTremblingAtTheStopDatesTheDepartureAtTheLastPointWithin20Metres() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 20)
        trace.tremble([3, -5, 2])
        let departure = trace.now
        trace.tremble([30, 22], reportedSpeed: nil)
        trace.gap(seconds: 3, speed: 8)
        trace.move(seconds: 5, speed: 8)

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.count == 2)
        #expect(decisions.last == .resume(at: departure))
    }

    @Test func aGPSTremblingAtTheStopDoesNotDateTheDepartureBeforeTheLastPointThere() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 20)
        trace.tremble([1, 4, 8, 3])
        let departure = trace.now
        trace.move(seconds: 5, speed: 7)

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.last == .resume(at: departure))
    }

    @Test func aTunnelNeverPauses() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.gap(seconds: 90, speed: 8)
        trace.move(seconds: 5, speed: 8, reportedSpeed: .some(nil), accuracy: 30)
        trace.move(seconds: 30, speed: 8)

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start).isEmpty)
    }

    @Test func unknownSpeedsWhileRidingNeverPause() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 120, speed: 5, reportedSpeed: .some(nil))

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start).isEmpty)
    }

    @Test func unknownSpeedsAtAStandstillPause() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 30, reportedSpeed: nil)

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.count == 1)
        #expect(decisions.first == .pause(at: start.addingTimeInterval(40), position: trace.coordinate(at: start.addingTimeInterval(30))))
    }

    @Test func aStopShorterThanTenSecondsDoesNotPause() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 9)
        trace.move(seconds: 30, speed: 8)

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start).isEmpty)
    }

    @Test func noGracePeriodAfterStart() {
        var trace = SyntheticTrace(start: start)
        trace.stand(seconds: 12)

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start)
            == [.pause(at: start.addingTimeInterval(10), position: trace.coordinate(at: start))])
    }

    @Test func isStationaryPausesAtOnce() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 2)
        trace.stationary()

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start)
            == [.pause(at: start.addingTimeInterval(32), position: trace.coordinate(at: start.addingTimeInterval(30)))])
    }

    @Test func slowDriftAroundThePausePositionDoesNotResume() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 15)
        trace.move(seconds: 19, speed: 1, reportedSpeed: 1)

        #expect(AutoPauseReplay.run(trace.signals, rule: .gps, since: start).count == 1)
    }

    @Test func resumesFortyMetresAwayWhateverTheSpeed() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 15)
        let departure = trace.now
        trace.move(seconds: 4, speed: 10, reportedSpeed: .some(nil))

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.last == .resume(at: departure))
    }

    @Test func afterAResumeTheNextStopPausesAgain() {
        var trace = SyntheticTrace(start: start)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 20)
        trace.move(seconds: 30, speed: 8)
        trace.stand(seconds: 20)

        let decisions = AutoPauseReplay.run(trace.signals, rule: .gps, since: start)

        #expect(decisions.count == 3)
        #expect(decisions.last == .pause(at: start.addingTimeInterval(90), position: trace.coordinate(at: start.addingTimeInterval(80))))
    }

    @Test func noSharedTestTraceGivesAPause() throws {
        let traces = try SharedTrace.all()
        #expect(!traces.isEmpty)
        for (name, trace) in traces {
            let signals = trace.samples.map(AutoPauseSignal.location)
            let since = try #require(trace.samples.first).timestamp
            for rule in [AutoPauseRule.gps, .motion] {
                let decisions = AutoPauseReplay.run(signals, rule: rule, since: since)
                #expect(decisions.filter(\.isPause).isEmpty, "\(name) with \(rule)")
            }
        }
    }
}

extension AutoPauseDecision {
    var isPause: Bool {
        if case .pause = self { true } else { false }
    }
}
