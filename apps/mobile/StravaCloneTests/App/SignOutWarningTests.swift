import Testing
@testable import StravaClone

/// The single sign-out confirmation (ADR-031 §14, ADR-030 §8): what would be lost.
struct SignOutWarningTests {
    @Test func nothingToLoseNeedsNoConfirmation() {
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 0, pendingItineraryChanges: 0) == nil)
    }

    @Test func itCountsTheActivitiesNotYetSent() {
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 1, pendingItineraryChanges: 0)
            == "1 activité pas encore envoyée sera perdue.")
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 2, pendingItineraryChanges: 0)
            == "2 activités pas encore envoyées seront perdues.")
    }

    @Test func oneConfirmationCoversTheRecordingTheActivitiesAndTheItineraryChanges() {
        let message = SignOutWarning.message(recordingInProgress: true, unsentActivities: 3, pendingItineraryChanges: 1)

        #expect(message == """
            L'enregistrement en cours sera supprimé.
            3 activités pas encore envoyées seront perdues.
            1 modification d'Itinéraire n'a pas encore été envoyée : elle sera perdue.
            """)
    }
}
