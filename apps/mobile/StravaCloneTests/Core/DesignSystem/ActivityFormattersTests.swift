import Foundation
import Testing
@testable import StravaClone

struct ActivityFormattersTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }()

    /// Friday 2 October 2026, 18:00 in Paris.
    private var now: Date { date(2026, 10, 2, 18, 0) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func relativeDates() {
        #expect(ActivityFormatters.relativeDateTime(date(2026, 10, 2, 14, 32), now: now, calendar: calendar) == "Aujourd'hui à 14:32")
        #expect(ActivityFormatters.relativeDateTime(date(2026, 10, 1, 8, 5), now: now, calendar: calendar) == "Hier à 08:05")
        #expect(ActivityFormatters.relativeDateTime(date(2026, 9, 28, 18, 10), now: now, calendar: calendar) == "lundi à 18:10")
        #expect(ActivityFormatters.relativeDateTime(date(2026, 9, 12, 7, 0), now: now, calendar: calendar) == "12 septembre à 07:00")
        #expect(ActivityFormatters.relativeDateTime(date(2025, 9, 12, 7, 0), now: now, calendar: calendar) == "12 septembre 2025 à 07:00")
    }

    @Test func distances() {
        #expect(ActivityFormatters.distance(Distance(meters: 10_234)) == "10,23 km")
        #expect(ActivityFormatters.distance(Distance(meters: 850.4)) == "850 m")
    }

    @Test func elevationAndDurations() {
        #expect(ActivityFormatters.elevation(245.4) == "245 m")
        #expect(ActivityFormatters.duration(.seconds(3_130)) == "52 min 10 s")
        #expect(ActivityFormatters.duration(.seconds(3_900)) == "1 h 05 min")
        #expect(ActivityFormatters.duration(.seconds(42)) == "42 s")
    }

    @Test func sportsAndShareText() {
        #expect(ActivityFormatters.sportLabel(.ride) == "Vélo")
        #expect(ActivityFormatters.sportSymbol(SportType(code: "kitesurf")) == "figure.mixed.cardio")
        #expect(ActivityFormatters.shareText(for: .fixture()) == "Sortie · Course à pied de 10,00 km à Annecy, Haute-Savoie 🏃")
    }
}
