import Foundation
import Testing
@testable import StravaClone

/// The finish screen's title (ADR-031 §11): the server's formula (`default-title.ts`), at the
/// phone's local time at Start.
struct DefaultActivityTitleTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    /// 2026-10-15 at `hour`:`minute` in Paris (UTC+2).
    private func parisTime(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 10, day: 15, hour: hour, minute: minute)
        components.timeZone = paris
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test(arguments: [
        (5, 0, "Course à pied le matin"),
        (11, 59, "Course à pied le matin"),
        (12, 0, "Course à pied l'après-midi"),
        (17, 59, "Course à pied l'après-midi"),
        (18, 0, "Course à pied le soir"),
        (21, 59, "Course à pied le soir"),
        (22, 0, "Course à pied de nuit"),
        (4, 59, "Course à pied de nuit"),
    ])
    func theTimeOfDayFollowsTheServersSlices(hour: Int, minute: Int, title: String) {
        #expect(DefaultActivityTitle.make(sport: .run, startedAt: parisTime(hour, minute), timeZone: paris) == title)
    }

    @Test func eachSportHasItsLabel() {
        let morning = parisTime(8)
        #expect(DefaultActivityTitle.make(sport: .ride, startedAt: morning, timeZone: paris) == "Sortie à vélo le matin")
        #expect(DefaultActivityTitle.make(sport: .walk, startedAt: morning, timeZone: paris) == "Marche le matin")
        #expect(DefaultActivityTitle.make(sport: .hike, startedAt: morning, timeZone: paris) == "Randonnée le matin")
    }

    @Test func theHourIsReadInThePhonesTimeZone() {
        // 07:00 in Paris is 01:00 in New York.
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(DefaultActivityTitle.make(sport: .run, startedAt: parisTime(7), timeZone: newYork) == "Course à pied de nuit")
    }

    @Test func anEmptyTitleFallsBackToTheDefault() {
        let start = parisTime(19)
        #expect(DefaultActivityTitle.resolve("   ", sport: .walk, startedAt: start, timeZone: paris) == "Marche le soir")
        #expect(DefaultActivityTitle.resolve(" Tour du lac ", sport: .walk, startedAt: start, timeZone: paris) == "Tour du lac")
    }

    @Test func aTitleIsCutToTheAPIsLimit() {
        let long = String(repeating: "a", count: 300)
        #expect(DefaultActivityTitle.resolve(long, sport: .run, startedAt: parisTime(9), timeZone: paris).count == 255)
    }
}
