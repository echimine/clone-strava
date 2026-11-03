import Foundation
@testable import StravaClone

/// In-memory `AthleteKudosRepository`: answers with the count the viewer's kudos makes, or a
/// scripted failure; records calls.
final class FakeAthleteKudosRepository: AthleteKudosRepository, @unchecked Sendable {
    private let lock = NSLock()

    var failure: AthleteError?
    /// The count the server answers.
    var kudosCount = 7

    private(set) var calls: [(given: Bool, activityId: ActivityID)] = []

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(AthleteError) -> KudosState {
        let (failure, count) = lock.withLock {
            calls.append((given, activityId))
            return (self.failure, kudosCount)
        }
        if let failure { throw failure }
        return KudosState(kudosCount: count, viewerHasKudoed: given)
    }
}
