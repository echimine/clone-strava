import Foundation
@testable import StravaClone

/// In-memory `ActivityResultsRepository`: answers scripted in order (the last one repeats),
/// recorded calls.
final class FakeActivityResultsRepository: ActivityResultsRepository, @unchecked Sendable {
    struct Removal: Equatable {
        let id: ActivityID
        let distanceM: Double
    }

    private let lock = NSLock()
    private var answers: [Result<ActivityResults, ActivityDetailError>]
    private(set) var requestedIds: [ActivityID] = []
    /// Answer of `removeBestEffort`; succeeds by default.
    var removeResult: Result<Void, ActivityDetailError> = .success(())
    private(set) var removals: [Removal] = []

    init(_ answers: Result<ActivityResults, ActivityDetailError>...) {
        self.answers = answers
    }

    func results(of id: ActivityID) async throws(ActivityDetailError) -> ActivityResults {
        let answer = lock.withLock {
            requestedIds.append(id)
            return answers.count > 1 ? answers.removeFirst() : answers.first ?? .failure(.network)
        }
        return try answer.get()
    }

    func removeBestEffort(of id: ActivityID, distanceM: Double) async throws(ActivityDetailError) {
        try lock.withLock {
            removals.append(Removal(id: id, distanceM: distanceM))
            return removeResult
        }.get()
    }
}

extension BestEffortResult {
    static func fixture(
        distanceM: Double = 1_000,
        seconds: Int = 280,
        medal: Medal? = nil,
        isFirst: Bool = false,
        isCurrentRecord: Bool = false,
        removable: Bool = true
    ) -> BestEffortResult {
        BestEffortResult(
            distanceM: distanceM,
            elapsedTime: .seconds(seconds),
            medal: medal,
            isFirst: isFirst,
            isCurrentRecord: isCurrentRecord,
            removable: removable
        )
    }
}

extension SegmentEffortResult {
    static func fixture(
        id: String = UUID().uuidString,
        name: String = "Montée du col",
        distanceM: Double = 370,
        seconds: Int = 131,
        medal: Medal? = nil,
        isFirstPass: Bool = false,
        localLegend: Bool = false
    ) -> SegmentEffortResult {
        SegmentEffortResult(
            id: id,
            segmentID: "seg-\(id)",
            segmentName: name,
            segmentDistance: Distance(meters: distanceM),
            verified: false,
            elapsedTime: .seconds(seconds),
            medal: medal,
            isFirstPass: isFirstPass,
            localLegend: localLegend,
            startPoint: Coordinate(latitude: 45.9, longitude: 6.13)
        )
    }
}
