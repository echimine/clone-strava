import Foundation
import Testing
@testable import StravaClone

struct ProgressCalendarTests {
    @Test func todayIsTheDayInParis() {
        // 2026-11-02T23:30Z is already 3 November, 00:30, in Paris.
        let now = Date(timeIntervalSince1970: 1_793_662_200)
        #expect(ProgressCalendar.today(now: now) == CalendarDay(year: 2026, month: 11, day: 3))
    }
}

struct StreakMonthTests {
    private func days(_ numbers: Int..., month: Int = 11, year: Int = 2026) -> Set<CalendarDay> {
        Set(numbers.map { CalendarDay(year: year, month: month, day: $0) })
    }

    @Test func november2026StartsOnASundayInAMondayFirstGrid() {
        let month = StreakMonth(today: CalendarDay(year: 2026, month: 11, day: 3), activeDays: [])

        #expect(month.weeks.count == 6)
        #expect(month.weeks[0].map { $0?.day } == [nil, nil, nil, nil, nil, nil, 1])
        #expect(month.weeks[1].map { $0?.day } == [2, 3, 4, 5, 6, 7, 8])
        #expect(month.weeks[5].map { $0?.day } == [30, nil, nil, nil, nil, nil, nil])
        #expect(month.weeks.allSatisfy { $0.count == 7 })
    }

    @Test func marksTheActiveDaysAndCirclesToday() {
        let month = StreakMonth(
            today: CalendarDay(year: 2026, month: 11, day: 3),
            activeDays: days(1, 3, 17)
        )
        let cells = month.weeks.flatMap { $0 }.compactMap { $0 }

        #expect(cells.filter(\.isActive).map(\.day) == [1, 3, 17])
        #expect(cells.filter(\.isToday).map(\.day) == [3])
        #expect(cells.count == 30)
    }

    @Test func ignoresDaysOfAnotherMonth() {
        let month = StreakMonth(
            today: CalendarDay(year: 2026, month: 11, day: 3),
            activeDays: days(31, month: 10)
        )

        #expect(month.weeks.flatMap { $0 }.compactMap { $0 }.allSatisfy { !$0.isActive })
    }

    @Test func aLeapFebruaryHas29Days() {
        // 1 February 2028 is a Tuesday.
        let month = StreakMonth(today: CalendarDay(year: 2028, month: 2, day: 29), activeDays: [])

        #expect(month.weeks[0].map { $0?.day } == [nil, 1, 2, 3, 4, 5, 6])
        #expect(month.weeks.flatMap { $0 }.compactMap { $0 }.last?.day == 29)
        #expect(month.weeks.last?.compactMap { $0 }.last?.isToday == true)
    }
}

struct AthleteProgressWeekTests {
    private let progress = AthleteProgress(
        sport: .run,
        weeks: [
            WeekProgress(weekStart: CalendarDay(year: 2026, month: 10, day: 26), distance: Distance(meters: 5_000), elevationGain: 0, movingTime: .zero, activityCount: 1),
            WeekProgress(weekStart: CalendarDay(year: 2026, month: 11, day: 2), distance: Distance(meters: 8_000), elevationGain: 0, movingTime: .zero, activityCount: 1),
        ],
        streakWeeks: 2,
        activeDays: []
    )

    @Test func thisWeekIsTheLastOne() {
        #expect(progress.thisWeek?.distance == Distance(meters: 8_000))
    }

    @Test func aTouchedDateSelectsTheWeekThatContainsIt() throws {
        let thursday = try #require(CalendarDay(year: 2026, month: 10, day: 29).startInParis)
        let sunday = try #require(CalendarDay(year: 2026, month: 11, day: 8).startInParis)
        let later = try #require(CalendarDay(year: 2026, month: 12, day: 1).startInParis)

        #expect(progress.week(containing: thursday)?.weekStart == CalendarDay(year: 2026, month: 10, day: 26))
        #expect(progress.week(containing: sunday)?.weekStart == CalendarDay(year: 2026, month: 11, day: 2))
        #expect(progress.week(containing: later) == nil)
    }
}
