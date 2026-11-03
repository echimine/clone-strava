import Foundation
import Testing
@testable import StravaClone

/// The Kudos and comments screen (ADR-036 §8): a segmented Kudos · N / Commentaires · N, opened
/// on the tab its request asks for.
@MainActor
struct ActivityEngagementStoreTests {
    @Test func aCommentButtonOpensTheCommentsWithTheComposerFocused() {
        let detail = ActivityDetail.fixture()

        let store = ActivityEngagementStore.over(.comments(detail.id), FakeActivityDetailRepository(.success(detail)))

        #expect(store.tab == .comments)
        #expect(store.comments.isComposerFocused)
    }

    @Test func theKudosRowOpensTheKudosWithoutTheKeyboard() {
        let detail = ActivityDetail.fixture()

        let store = ActivityEngagementStore.over(.kudos(detail.id), FakeActivityDetailRepository(.success(detail)))

        #expect(store.tab == .kudos)
        #expect(!store.comments.isComposerFocused)
    }

    @Test func theSegmentsShowTheCountsOnceLoaded() async {
        let engagement = ActivityEngagement(kudosCount: 4, commentCount: 1, viewerHasKudoed: false)
        let detail = ActivityDetail.fixture(engagement: engagement)
        let store = ActivityEngagementStore.over(.kudos(detail.id), FakeActivityDetailRepository(.success(detail)))
        #expect(store.kudosTitle == "Kudos")
        #expect(store.commentsTitle == "Commentaires")

        await store.load()

        #expect(store.kudosTitle == "Kudos · 4")
        #expect(store.commentsTitle == "Commentaires · 1")
    }

    /// The Kudos segment lists the givers page by page (ADR-034 §1), the sheet's former list.
    @Test func theKudosSegmentListsEveryGiver() async {
        let detail = ActivityDetail.fixture()
        let givers = KudosGiver.fixtures(0 ..< 3)
        let store = ActivityEngagementStore.over(
            .kudos(detail.id),
            FakeActivityDetailRepository(.success(detail)),
            kudos: FakeActivityKudosRepository(.success(KudosPage(givers: givers, nextCursor: nil)))
        )

        await store.kudos.load()

        #expect(store.kudos.givers == givers)
    }

    @Test func aCommentSentRaisesTheCommentsCount() async {
        let detail = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 0, viewerHasKudoed: false))
        let store = ActivityEngagementStore.over(.comments(detail.id), FakeActivityDetailRepository(.success(detail)))
        await store.load()

        store.comments.draft = "Bravo !"
        await store.comments.send()

        #expect(store.commentsTitle == "Commentaires · 1")
    }
}
