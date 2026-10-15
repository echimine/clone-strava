import Foundation
import Testing
@testable import StravaClone

struct RecordingSaveBlockerTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func finished(_ sport: RecordingSport, after seconds: TimeInterval) -> Recording {
        var recording = Recording(sport: sport, startedAt: start)
        recording.pause(at: start.addingTimeInterval(seconds))
        recording.finish()
        return recording
    }

    @Test func belowTheSportsMinimumDurationSaveIsDisabled() {
        #expect(RecordingSaveBlocker(recording: finished(.run, after: 59), pointCount: 60) == .tooShort(minimum: .seconds(60)))
        #expect(RecordingSaveBlocker(recording: finished(.run, after: 60), pointCount: 60) == nil)
        #expect(RecordingSaveBlocker(recording: finished(.hike, after: 299), pointCount: 300) == .tooShort(minimum: .seconds(300)))
    }

    @Test func withFewerThanTwoPointsSaveIsDisabled() {
        #expect(RecordingSaveBlocker(recording: finished(.ride, after: 600), pointCount: 1) == .notEnoughPoints)
        #expect(RecordingSaveBlocker(recording: finished(.ride, after: 600), pointCount: 2) == nil)
    }
}
