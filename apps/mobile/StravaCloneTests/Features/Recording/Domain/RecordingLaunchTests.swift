import Testing
@testable import StravaClone

/// ADR-031 §10: which launch picks a stored Recording up as it was, and which one is the
/// athlete opening the app (an `active` Recording then reopens paused).
struct RecordingLaunchTests {
    @Test func aLaunchForLocationIsABackgroundRelaunch() {
        #expect(RecordingLaunch(launchedForLocation: true, inBackground: true) == .relaunchedInBackground)
    }

    /// The `BGAppRefreshTask` of the sync queue, or a `liveUpdates` relaunch without the key.
    @Test func anyOtherLaunchInTheBackgroundIsABackgroundRelaunchToo() {
        #expect(RecordingLaunch(launchedForLocation: false, inBackground: true) == .relaunchedInBackground)
    }

    @Test func aLaunchInTheForegroundIsTheAthleteOpeningTheApp() {
        #expect(RecordingLaunch(launchedForLocation: false, inBackground: false) == .openedByAthlete)
    }

    @Test func theLocationKeyAloneIsEnoughEvenIfTheStateSaysOtherwise() {
        #expect(RecordingLaunch(launchedForLocation: true, inBackground: false) == .relaunchedInBackground)
    }
}
