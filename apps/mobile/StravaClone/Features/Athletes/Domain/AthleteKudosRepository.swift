import Foundation

/// Kudos on another athlete's Activities, from their profile's cards (ADR-029, ADR-036 §3).
protocol AthleteKudosRepository: Sendable {
    func setKudos(_ given: Bool, activityId: ActivityID) async throws(AthleteError) -> KudosState
}
