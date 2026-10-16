import Foundation

/// Someone who gave kudos to an Activity, and when (ADR-034 §1). Not tappable: there is no
/// athlete profile yet.
struct KudosGiver: Identifiable, Hashable, Sendable {
    let athlete: ActivityAuthor
    let givenAt: Date

    /// One kudos per athlete and Activity.
    var id: String { athlete.id }
}

/// A page of kudos, most recent first; `nextCursor` is nil on the last page.
struct KudosPage: Equatable, Sendable {
    let givers: [KudosGiver]
    let nextCursor: String?
}

/// Kudos of one Activity (ADR-007 port): who gave them (`GET /v1/activities/:id/kudos`), and
/// giving or removing the viewer's own (ADR-029). Implemented over the API, faked in tests.
protocol ActivityKudosRepository: Sendable {
    func kudos(activityId: ActivityID, cursor: String?, limit: Int) async throws(ActivityDetailError) -> KudosPage
    /// Gives (`true`) or removes (`false`); returns the server's state.
    func setKudos(_ given: Bool, activityId: ActivityID) async throws(ActivityDetailError) -> KudosState
}
