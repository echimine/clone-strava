import Foundation
@testable import StravaClone

extension ActivityEngagementStore {
    /// The Kudos and comments screen over fakes, wired as the app shell does: its Activity's
    /// store holds the counts and publishes them on `changes`.
    static func over(
        _ request: ActivityEngagementRequest,
        _ details: FakeActivityDetailRepository,
        kudos: FakeActivityKudosRepository = FakeActivityKudosRepository(),
        comments: FakeActivityCommentRepository = FakeActivityCommentRepository(),
        changes: ActivityChanges = ActivityChanges()
    ) -> ActivityEngagementStore {
        let detail = ActivityDetailStore(
            id: request.activityId,
            loadDetail: LoadActivityDetail(repository: details),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            updateActivity: UpdateActivity(repository: details),
            deleter: .over(details, changes: changes)
        )
        return ActivityEngagementStore(
            request: request,
            detail: detail,
            comments: .forDetail(detail, request: request, repository: comments)
        )
    }
}
