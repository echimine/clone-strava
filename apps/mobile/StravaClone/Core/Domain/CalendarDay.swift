import Foundation

/// A day on the calendar, without time or time zone (`YYYY-MM-DD` in the contracts): a birth
/// date (ADR-035 §5), a week's Monday or an active day of Progrès (ADR-036 §4).
struct CalendarDay: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// The day `date` falls on in `calendar`.
    init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// The day `date` falls on in UTC: the day the server checks the minimum age on (ADR-035
    /// §5), so the app never lets through an age the server refuses.
    static func utc(_ date: Date) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return CalendarDay(date, calendar: calendar)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`; `nil` for anything else.
    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon of that day in `calendar`, safe from daylight saving changes.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    /// Whole years from `self` to `day`: a birthday counts from its very day (a 29 February
    /// counts from 1 March in other years).
    func years(until day: CalendarDay) -> Int {
        let hadBirthday = (day.month, day.day) >= (month, self.day)
        return day.year - year - (hadBirthday ? 0 : 1)
    }
}
