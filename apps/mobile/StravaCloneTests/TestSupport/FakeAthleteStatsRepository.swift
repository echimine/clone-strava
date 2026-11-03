import Foundation
@testable import StravaClone

/// In-memory `AthleteStatsRepository` (ADR-025 §3): answers per sport (`nil` = all sports),
/// recorded calls.
final class FakeAthleteStatsRepository: AthleteStatsRepository, @unchecked Sendable {
    private let lock = NSLock()

    var results: [SportType?: Result<AthleteStats, AthleteError>] = [:]
    private(set) var calls: [(athleteId: String, sport: SportType?)] = []

    /// Answers all sports with `AthleteStats.fixture(sport: nil)`: 412 km this year.
    static func allSports() -> FakeAthleteStatsRepository {
        let repository = FakeAthleteStatsRepository()
        repository.results[nil] = .success(.fixture(sport: nil))
        return repository
    }

    func stats(of athleteId: String, sport: SportType?) async throws(AthleteError) -> AthleteStats {
        let result = lock.withLock {
            calls.append((athleteId, sport))
            return results[sport] ?? .failure(.network)
        }
        return try result.get()
    }
}

extension AthleteStats {
    static func fixture(sport: SportType?, yearToDateCount: Int = 40) -> AthleteStats {
        AthleteStats(
            sport: sport,
            recent: Recent(activitiesPerWeek: 1.5, movingTimePerWeek: .seconds(3_600), distancePerWeek: Distance(meters: 12_000)),
            yearToDate: YearToDate(
                activityCount: yearToDateCount,
                movingTime: .seconds(90_000),
                distance: Distance(meters: 412_000),
                elevationGain: 3_000
            ),
            allTime: AllTime(activityCount: 80, distance: Distance(meters: 900_000), elevationGain: 7_000)
        )
    }
}
