import Foundation

extension CalendarDay {
    /// Midnight of this day in Paris, where weeks are counted (ADR-036 §4).
    var startInParis: Date? {
        ProgressCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// The athlete's calendar (ADR-036 §4): weeks from Monday, in `Europe/Paris`, like the server's
/// `ATHLETE_TIME_ZONE`.
enum ProgressCalendar {
    static let timeZone = TimeZone(identifier: "Europe/Paris")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }()

    static func today(now: Date = .now) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }
}

/// One week of the Progrès tab: totals of one sport from Monday to Sunday.
struct WeekProgress: Equatable, Sendable {
    let weekStart: CalendarDay
    let distance: Distance
    let elevationGain: Double
    let movingTime: Duration
    let activityCount: Int
}

/// My Progrès for one sport (`GET /v1/me/progress`, ADR-036 §4): 12 weeks oldest first, ending
/// with the current one, then the Série.
struct AthleteProgress: Equatable, Sendable {
    let sport: SportType
    let weeks: [WeekProgress]
    /// Consecutive weeks with an Activity of this sport.
    let streakWeeks: Int
    /// The current month's days with an Activity of this sport.
    let activeDays: Set<CalendarDay>

    /// "Cette semaine".
    var thisWeek: WeekProgress? { weeks.last }

    /// The week a touch on the chart lands in; nil outside the 12 weeks.
    func week(containing date: Date) -> WeekProgress? {
        weeks.first { week in
            guard let start = week.weekStart.startInParis,
                  let end = ProgressCalendar.calendar.date(byAdding: .day, value: 7, to: start) else { return false }
            return start <= date && date < end
        }
    }
}

/// My Progrès (ADR-036 §4), own profile only. Implemented over the API, faked in tests.
protocol ProgressRepository: Sendable {
    func progress(sport: SportType) async throws(AthleteError) -> AthleteProgress
}

/// The Série card's calendar (ADR-036 §4): the current month in weeks from Monday, days with
/// an Activity filled and today circled. Empty cells pad the first and last weeks.
struct StreakMonth: Equatable, Sendable {
    struct Cell: Equatable, Sendable {
        let day: Int
        let isActive: Bool
        let isToday: Bool
    }

    let year: Int
    let month: Int
    /// Rows of 7 cells, Monday to Sunday.
    let weeks: [[Cell?]]

    init(today: CalendarDay, activeDays: Set<CalendarDay>) {
        year = today.year
        month = today.month
        let calendar = ProgressCalendar.calendar
        let first = calendar.date(from: DateComponents(year: today.year, month: today.month, day: 1))!
        let dayCount = calendar.range(of: .day, in: .month, for: first)!.count
        // Monday = 0 … Sunday = 6.
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Cell?] = Array(repeating: nil, count: leading)
        for day in 1...dayCount {
            let calendarDay = CalendarDay(year: today.year, month: today.month, day: day)
            cells.append(Cell(day: day, isActive: activeDays.contains(calendarDay), isToday: calendarDay == today))
        }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}
