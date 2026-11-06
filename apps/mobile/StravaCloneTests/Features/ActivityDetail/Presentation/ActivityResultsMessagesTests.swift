import Testing
@testable import StravaClone

/// The note under the Segments of « Résultats » (spec #252): an Activity that is not public does
/// not count on the Leaderboard, worded for its author or, neutrally, for anyone else.
struct ActivityResultsMessagesTests {
    @Test func aPublicActivityHasNoNote() {
        #expect(ActivityResultsMessages.notOnLeaderboard(.public, viewerIsAuthor: true) == nil)
        #expect(ActivityResultsMessages.notOnLeaderboard(.public, viewerIsAuthor: false) == nil)
    }

    @Test func theAuthorReadsAboutTheirFollowers() {
        #expect(
            ActivityResultsMessages.notOnLeaderboard(.followers, viewerIsAuthor: true)
                == "Activité visible par tes abonnés : ses Efforts ne comptent pas au Classement."
        )
    }

    /// Someone else's Activity is not « visible par tes abonnés ».
    @Test func anotherAthleteReadsANeutralNote() {
        #expect(
            ActivityResultsMessages.notOnLeaderboard(.followers, viewerIsAuthor: false)
                == "Activité réservée aux abonnés : ses Efforts ne comptent pas au Classement."
        )
    }

    @Test func aPrivateActivityReadsTheSameForEveryone() {
        let note = "Activité privée : ses Efforts ne comptent pas au Classement."
        #expect(ActivityResultsMessages.notOnLeaderboard(.private, viewerIsAuthor: true) == note)
        #expect(ActivityResultsMessages.notOnLeaderboard(.private, viewerIsAuthor: false) == note)
    }
}
