import Foundation
import Testing
@testable import StravaClone

struct RecordingSaveBlockerTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let farEnough = Distance(meters: 1_000)

    private func finished(_ sport: RecordingSport, after seconds: TimeInterval, pausedFor pause: TimeInterval = 0) -> Recording {
        var recording = Recording(sport: sport, startedAt: start)
        if pause > 0 {
            recording.pause(at: start.addingTimeInterval(1))
            recording.resume(at: start.addingTimeInterval(1 + pause))
        }
        recording.pause(at: start.addingTimeInterval(seconds + pause))
        recording.finish()
        return recording
    }

    @Test func belowTheSportsMinimumDurationSaveIsDisabled() {
        #expect(RecordingSaveBlocker(recording: finished(.run, after: 59), pointCount: 60, distance: farEnough) == .tooShort(minimum: .seconds(60)))
        #expect(RecordingSaveBlocker(recording: finished(.run, after: 60), pointCount: 60, distance: farEnough) == nil)
        #expect(RecordingSaveBlocker(recording: finished(.hike, after: 299), pointCount: 300, distance: farEnough) == .tooShort(minimum: .seconds(300)))
    }

    /// The minimum is on the timer, Pauses out: 30 s of motion in 2 min do not make the minute.
    @Test func pausesDoNotCountTowardsTheMinimumDuration() {
        #expect(RecordingSaveBlocker(recording: finished(.walk, after: 30, pausedFor: 90), pointCount: 60, distance: farEnough) == .tooShort(minimum: .seconds(60)))
    }

    @Test func belowTheSportsMinimumDistanceSaveIsDisabled() {
        #expect(RecordingSaveBlocker(recording: finished(.walk, after: 600), pointCount: 60, distance: .zero) == .notFarEnough(minimum: Distance(meters: 100)))
        #expect(RecordingSaveBlocker(recording: finished(.walk, after: 600), pointCount: 60, distance: Distance(meters: 100)) == nil)
        #expect(RecordingSaveBlocker(recording: finished(.ride, after: 600), pointCount: 60, distance: Distance(meters: 199)) == .notFarEnough(minimum: Distance(meters: 200)))
        #expect(RecordingSaveBlocker(recording: finished(.hike, after: 600), pointCount: 60, distance: Distance(meters: 199)) == .notFarEnough(minimum: Distance(meters: 200)))
        #expect(RecordingSaveBlocker(recording: finished(.run, after: 600), pointCount: 60, distance: Distance(meters: 99)) == .notFarEnough(minimum: Distance(meters: 100)))
    }

    @Test func withFewerThanTwoPointsSaveIsDisabled() {
        #expect(RecordingSaveBlocker(recording: finished(.ride, after: 600), pointCount: 1, distance: farEnough) == .notEnoughPoints)
        #expect(RecordingSaveBlocker(recording: finished(.ride, after: 600), pointCount: 2, distance: farEnough) == nil)
    }
}
