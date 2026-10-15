import Foundation
import Testing
@testable import StravaClone

/// What a Recording keeps of the automatic Pause (ADR-031 §4, §10).
struct RecordingAutoPauseTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let position = Coordinate(latitude: 45.764, longitude: 4.8357)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func autoPauseIsOnByDefaultForARideOfferedForARunAndAbsentOnFoot() {
        #expect(RecordingSport.ride.autoPauseRule == .gps)
        #expect(RecordingSport.ride.autoPauseByDefault)
        #expect(RecordingSport.run.autoPauseRule == .motion)
        #expect(!RecordingSport.run.autoPauseByDefault)
        #expect(RecordingSport.walk.autoPauseRule == nil)
        #expect(RecordingSport.hike.autoPauseRule == nil)
    }

    @Test func aPauseIsManualUnlessTheRulesStartedIt() {
        var manual = Recording(sport: .ride, startedAt: start, autoPauseEnabled: true)
        manual.pause(at: at(10))
        #expect(manual.currentPauseKind == .manual)
        #expect(!manual.isAutomaticallyPaused)

        var automatic = Recording(sport: .ride, startedAt: start, autoPauseEnabled: true)
        automatic.pause(at: at(10), kind: .automatic, position: position)
        #expect(automatic.currentPauseKind == .automatic)
        #expect(automatic.currentPausePosition == position)
        #expect(automatic.isAutomaticallyPaused)

        automatic.resume(at: at(30))
        #expect(automatic.currentPauseKind == nil)
        #expect(automatic.currentPausePosition == nil)
        #expect(automatic.pauses == [RecordingPause(start: at(10), end: at(30))])
    }

    @Test func turningTheSwitchOffKeepsThePause() {
        var recording = Recording(sport: .ride, startedAt: start, autoPauseEnabled: true)
        recording.pause(at: at(10), kind: .automatic, position: position)

        recording.autoPauseEnabled = false

        #expect(recording.phase == .paused)
    }
}
