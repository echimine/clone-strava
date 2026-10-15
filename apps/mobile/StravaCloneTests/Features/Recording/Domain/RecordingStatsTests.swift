import Foundation
import Testing
@testable import StravaClone

struct RecordingStatsTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func averagesUseTheTimerSoPausesDoNotCount() {
        // 10 min of timer for 2 km, after a 5 min Pause.
        let stats = RecordingStats(sport: .run, elapsed: .seconds(600), distance: Distance(meters: 2_000), currentSpeedMs: nil)

        #expect(stats.averagePace == .seconds(300))
        #expect(abs(stats.averageSpeedMs - 3.333) < 0.001)
    }

    @Test func averagePaceShowsNothingForTheFirstThirtySeconds() {
        let early = RecordingStats(sport: .run, elapsed: .seconds(29), distance: Distance(meters: 100), currentSpeedMs: nil)
        let later = RecordingStats(sport: .run, elapsed: .seconds(30), distance: Distance(meters: 100), currentSpeedMs: nil)

        #expect(early.averagePace == nil)
        #expect(later.averagePace == .seconds(300))
    }

    @Test func averagePaceShowsNothingBeyondFiftyNineFiftyNinePerKilometer() {
        let slow = RecordingStats(sport: .walk, elapsed: .seconds(3_600), distance: Distance(meters: 1_000), currentSpeedMs: nil)
        let still = RecordingStats(sport: .walk, elapsed: .seconds(60), distance: .zero, currentSpeedMs: nil)

        #expect(slow.averagePace == nil)
        #expect(still.averagePace == nil)
        #expect(still.averageSpeedMs == 0)
    }

    @Test func currentSpeedIsTheDistanceOfTheLastFiveSeconds() {
        var speed = CurrentSpeed(movingSince: start)
        for second in 1...20 {
            // 5 m per second, then 10 m per second for the last 5 s.
            speed.record(Distance(meters: second > 15 ? 10 : 5), at: at(Double(second)))
        }

        #expect(speed.speedMs(at: at(20)) == 10)
    }

    @Test func currentSpeedDropsToZeroWhenNoMovementArrives() {
        var speed = CurrentSpeed(movingSince: start)
        speed.record(Distance(meters: 5), at: at(10))

        #expect(speed.speedMs(at: at(16)) == 0)
    }

    @Test func currentSpeedWindowRestartsOnResume() {
        var speed = CurrentSpeed(movingSince: start)
        speed.record(Distance(meters: 50), at: at(10))

        speed.reset(movingSince: at(100))
        speed.record(Distance(meters: 4), at: at(101))
        speed.record(Distance(meters: 4), at: at(102))

        // 8 m over the 2 s since Resume, nothing from before the Pause.
        #expect(speed.speedMs(at: at(102)) == 4)
        #expect(speed.speedMs(at: at(100)) == nil)
    }
}
