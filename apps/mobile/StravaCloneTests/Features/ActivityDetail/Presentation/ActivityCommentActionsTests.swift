import Foundation
import Testing
@testable import StravaClone

/// The long press on a comment (ADR-034 §6): "Modifier" and "Supprimer" on mine, only
/// "Supprimer" on others' when I wrote the Activity, nothing otherwise. The API says who may
/// do what (`viewerCanEdit` / `viewerCanDelete`, ADR-034 §3).
struct ActivityCommentActionsTests {
    private typealias Row = ActivityCommentsStore.Row

    @Test func myCommentCanBeEditedAndDeletedWhoeverWroteTheActivity() {
        // Mine, on my Activity or on someone else's: the API answers the same flags.
        let mine = ActivityComment.fixture(mine: true)

        #expect(Row(comment: mine, status: .sent).actions == [.edit, .delete])
    }

    @Test func onMyActivitySomeoneElsesCommentCanOnlyBeDeleted() {
        let theirs = ActivityComment.fixture(mine: false, viewerCanDelete: true)

        #expect(Row(comment: theirs, status: .sent).actions == [.delete])
    }

    @Test func onSomeoneElsesActivityTheirCommentsOfferNothing() {
        let theirs = ActivityComment.fixture(mine: false, viewerCanDelete: false)

        #expect(Row(comment: theirs, status: .sent).actions.isEmpty)
    }

    @Test func aCommentNotSentYetOffersNothing() {
        let mine = ActivityComment.fixture(mine: true)

        #expect(Row(comment: mine, status: .sending).actions.isEmpty)
        #expect(Row(comment: mine, status: .failed).actions.isEmpty)
    }
}
