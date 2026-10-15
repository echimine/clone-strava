import Foundation
import Testing
@testable import StravaClone

struct RecordingTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func timerRunsFromStartWithoutWaitingForTheGPS() {
        let recording = Recording(sport: .run, startedAt: start)

        #expect(recording.phase == .active)
        #expect(recording.elapsed(at: at(75)) == .seconds(75))
    }

    @Test func timerStopsDeadDuringAPauseAndSkipsItAfterResume() {
        var recording = Recording(sport: .run, startedAt: start)

        recording.pause(at: at(100))
        #expect(recording.phase == .paused)
        #expect(recording.elapsed(at: at(160)) == .seconds(100))

        let pause = recording.resume(at: at(400))
        #expect(pause == RecordingPause(start: at(100), end: at(400)))
        #expect(recording.phase == .active)
        #expect(recording.elapsed(at: at(450)) == .seconds(150))
    }

    @Test func finishingKeepsTheFinalPauseOpenAndEndsAtItsStart() {
        var recording = Recording(sport: .ride, startedAt: start)
        recording.pause(at: at(30))
        _ = recording.resume(at: at(90))
        recording.pause(at: at(200))

        recording.finish()

        #expect(recording.phase == .finishing)
        #expect(recording.endedAt == at(200))
        #expect(recording.pauses == [RecordingPause(start: at(30), end: at(90))])
        #expect(recording.elapsed(at: at(1_000)) == .seconds(140))
    }

    @Test func resumingFromTheFinishScreenGoesBackToThePause() {
        var recording = Recording(sport: .walk, startedAt: start)
        recording.pause(at: at(120))
        recording.finish()

        recording.reopen()

        #expect(recording.phase == .paused)
        // The time spent on the finish screen counts in the Pause.
        let pause = recording.resume(at: at(500))
        #expect(pause == RecordingPause(start: at(120), end: at(500)))
    }

    @Test func finishIsOnlyReachableFromAPause() {
        var recording = Recording(sport: .run, startedAt: start)

        recording.finish()

        #expect(recording.phase == .active)
        #expect(recording.endedAt == nil)
    }
}
