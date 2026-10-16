import Foundation

/// One page of who gave kudos to an Activity, most recent first (ADR-034 §1).
struct LoadKudosList: Sendable {
    let repository: any ActivityKudosRepository

    func callAsFunction(_ activityId: ActivityID, cursor: String? = nil, limit: Int) async throws(ActivityDetailError) -> KudosPage {
        try await repository.kudos(activityId: activityId, cursor: cursor, limit: limit)
    }
}

/// Gives or removes the viewer's kudos from the Activity detail (ADR-034 §1).
struct SetActivityKudos: Sendable {
    let repository: any ActivityKudosRepository

    func callAsFunction(_ given: Bool, activityId: ActivityID) async throws(ActivityDetailError) -> KudosState {
        try await repository.setKudos(given, activityId: activityId)
    }
}
