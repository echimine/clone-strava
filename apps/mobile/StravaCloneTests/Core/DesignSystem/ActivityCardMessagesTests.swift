import Foundation
import Testing
@testable import StravaClone

/// The card's social row text (ADR-036 §5): each part hidden at zero.
struct ActivityCardMessagesTests {
    @Test func theSocialSummaryFollowsTheCounts() {
        #expect(ActivityCardMessages.socialSummary(kudosCount: 0, commentCount: 0) == nil)
        #expect(ActivityCardMessages.socialSummary(kudosCount: 1, commentCount: 0) == "1 a envoyé des kudos")
        #expect(ActivityCardMessages.socialSummary(kudosCount: 3, commentCount: 0) == "3 ont envoyé des kudos")
        #expect(ActivityCardMessages.socialSummary(kudosCount: 0, commentCount: 1) == "1 commentaire")
        #expect(ActivityCardMessages.socialSummary(kudosCount: 1_204, commentCount: 2) == "1\u{202F}204 ont envoyé des kudos · 2 commentaires")
    }
}
