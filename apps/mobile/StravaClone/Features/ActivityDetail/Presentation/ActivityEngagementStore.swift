import Foundation
import Observation

/// The Kudos and comments screen of an Activity (ADR-036 §8): a segmented Kudos · N /
/// Commentaires · N over the paged list of givers and the comment thread.
///
/// Its Activity's store holds the counts: what the thread gains or loses reaches it, and from
/// there the feed card (ADR-033 §7, ADR-034 §6), whether the screen was pushed from the card or
/// from the detail.
@Observable
@MainActor
final class ActivityEngagementStore {
    typealias Tab = ActivityEngagementRequest.Tab

    /// The segment shown.
    var tab: Tab
    /// The Activity, for its counts, its availability and its live updates.
    let detail: ActivityDetailStore
    let comments: ActivityCommentsStore
    let kudos: KudosListStore

    /// - Parameter comments: `detail`'s thread (`ActivityCommentsStore.forDetail`).
    init(request: ActivityEngagementRequest, detail: ActivityDetailStore, comments: ActivityCommentsStore) {
        tab = request.tab
        self.detail = detail
        self.comments = comments
        kudos = detail.makeKudosListStore()
    }

    var activityId: ActivityID { detail.id }

    var kudosTitle: String {
        ActivityEngagementMessages.kudosTab(detail.detail?.engagement.kudosCount)
    }

    var commentsTitle: String {
        ActivityEngagementMessages.commentsTab(detail.detail?.engagement.commentCount)
    }

    /// On each appearance: the Activity and its counts (also "Réessayer" after an error).
    func load() async {
        await detail.load()
    }
}
