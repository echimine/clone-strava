import Testing
@testable import StravaClone

/// The single sign-out confirmation (ADR-031 §14, ADR-030 §8): what would be lost.
struct SignOutWarningTests {
    @Test func nothingToLoseNeedsNoConfirmation() {
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 0, unsentMedia: 0, pendingItineraryChanges: 0) == nil)
    }

    @Test func itCountsTheActivitiesNotYetSent() {
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 1, unsentMedia: 0, pendingItineraryChanges: 0)
            == "1 activité pas encore envoyée sera perdue.")
        #expect(SignOutWarning.message(recordingInProgress: false, unsentActivities: 2, unsentMedia: 0, pendingItineraryChanges: 0)
            == "2 activités pas encore envoyées seront perdues.")
    }

    /// ADR-037 §6: the Media not yet sent are lost too, counted on the Activities' line.
    @Test func itCountsTheMediaNotYetSentWithTheActivities() {
        func message(_ activities: Int, _ media: Int) -> String? {
            SignOutWarning.message(recordingInProgress: false, unsentActivities: activities, unsentMedia: media, pendingItineraryChanges: 0)
        }

        #expect(message(0, 1) == "1 média pas encore envoyé sera perdu.")
        #expect(message(0, 3) == "3 médias pas encore envoyés seront perdus.")
        #expect(message(2, 3) == "2 activités et 3 médias pas encore envoyés seront perdus.")
        #expect(message(1, 1) == "1 activité et 1 média pas encore envoyés seront perdus.")
    }

    @Test func oneConfirmationCoversTheRecordingTheActivitiesAndTheItineraryChanges() {
        let message = SignOutWarning.message(recordingInProgress: true, unsentActivities: 3, unsentMedia: 0, pendingItineraryChanges: 1)

        #expect(message == """
            L'enregistrement en cours sera supprimé.
            3 activités pas encore envoyées seront perdues.
            1 modification d'Itinéraire n'a pas encore été envoyée : elle sera perdue.
            """)
    }
}
