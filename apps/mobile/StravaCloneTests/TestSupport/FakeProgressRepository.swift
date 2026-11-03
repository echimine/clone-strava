import Foundation
@testable import StravaClone

/// In-memory `ProgressRepository` (ADR-025 §3): answers per sport, recorded calls.
final class FakeProgressRepository: ProgressRepository, @unchecked Sendable {
    private let lock = NSLock()

    var results: [SportType: Result<AthleteProgress, AthleteError>] = [:]
    private(set) var calls: [SportType] = []

    func progress(sport: SportType) async throws(AthleteError) -> AthleteProgress {
        let result = lock.withLock {
            calls.append(sport)
            return results[sport] ?? .failure(.network)
        }
        return try result.get()
    }
}

extension AthleteProgress {
    /// 12 weeks ending with the week of 2 November 2026; `thisWeekKm` for the last one.
    static func fixture(sport: SportType, thisWeekKm: Double = 21, streakWeeks: Int = 5, activeDays: [Int] = [1, 3]) -> AthleteProgress {
        let calendar = ProgressCalendar.calendar
        let lastMonday = CalendarDay(year: 2026, month: 11, day: 2).startInParis!
        let weeks = (0..<12).map { index in
            let start = calendar.date(byAdding: .day, value: (index - 11) * 7, to: lastMonday)!
            let components = calendar.dateComponents([.year, .month, .day], from: start)
            return WeekProgress(
                weekStart: CalendarDay(year: components.year!, month: components.month!, day: components.day!),
                distance: Distance(meters: index == 11 ? thisWeekKm * 1_000 : 10_000),
                elevationGain: 100,
                movingTime: .seconds(3_600),
                activityCount: 1
            )
        }
        return AthleteProgress(
            sport: sport,
            weeks: weeks,
            streakWeeks: streakWeeks,
            activeDays: Set(activeDays.map { CalendarDay(year: 2026, month: 11, day: $0) })
        )
    }
}
