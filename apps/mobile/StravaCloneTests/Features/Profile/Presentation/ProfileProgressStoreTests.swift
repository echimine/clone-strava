import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ProfileProgressStoreTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 3)

    private func makeStore(_ repository: FakeProgressRepository) -> ProfileProgressStore {
        let today = today
        return ProfileProgressStore(loadProgress: LoadProgress(repository: repository), today: { today })
    }

    @Test func opensOnMyFirstPracticedSport() async {
        let repository = FakeProgressRepository()
        repository.results[.ride] = .success(.fixture(sport: .ride))
        let store = makeStore(repository)

        await store.load(practicedSports: [.ride, .run])
        await store.load(practicedSports: [.ride, .run])

        #expect(store.sports == [.ride, .run])
        #expect(store.sport == .ride)
        #expect(store.progress == .fixture(sport: .ride))
        #expect(store.phase == .loaded)
        #expect(repository.calls == [.ride])
    }

    /// ADR-036 §3: an empty list hides the pills; nothing to load, Progrès says so.
    @Test func withoutPracticedSportsItHasNoPillsAndShowsTheEmptyState() async {
        let repository = FakeProgressRepository()
        let store = makeStore(repository)

        await store.load(practicedSports: [])

        #expect(store.sports.isEmpty)
        #expect(store.sport == nil)
        #expect(store.progress == nil)
        #expect(store.phase == .empty)
        #expect(repository.calls.isEmpty)
    }

    @Test func practicedSportsThatAppearLaterAreLoaded() async {
        let repository = FakeProgressRepository()
        repository.results[.run] = .success(.fixture(sport: .run))
        let store = makeStore(repository)
        await store.load(practicedSports: [])

        await store.load(practicedSports: [.run])

        #expect(store.sport == .run)
        #expect(store.phase == .loaded)
        #expect(repository.calls == [.run])
    }

    @Test func changingThePillReloadsTheWholeTabForThatSport() async throws {
        let repository = FakeProgressRepository()
        repository.results[.run] = .success(.fixture(sport: .run, thisWeekKm: 21, streakWeeks: 5, activeDays: [1, 3]))
        repository.results[.ride] = .success(.fixture(sport: .ride, thisWeekKm: 80, streakWeeks: 2, activeDays: [2]))
        let store = makeStore(repository)
        await store.load(practicedSports: [.run, .ride])
        store.selectedDate = try #require(CalendarDay(year: 2026, month: 10, day: 28).startInParis)
        #expect(store.selectedWeek != nil)

        await store.select(.ride)

        #expect(store.sport == .ride)
        #expect(store.progress?.thisWeek?.distance == Distance(meters: 80_000))
        #expect(store.progress?.streakWeeks == 2)
        let activeDays = store.month?.weeks.flatMap { $0 }.compactMap { $0 }.filter(\.isActive).map(\.day)
        #expect(activeDays == [2])
        #expect(store.selectedDate == nil)
        #expect(repository.calls == [.run, .ride])
    }

    @Test func theSeriesCalendarIsThisMonthWithTodayCircled() async {
        let repository = FakeProgressRepository()
        repository.results[.run] = .success(.fixture(sport: .run, activeDays: [1, 3]))
        let store = makeStore(repository)

        await store.load(practicedSports: [.run])

        let cells = store.month?.weeks.flatMap { $0 }.compactMap { $0 } ?? []
        #expect(store.month?.month == 11)
        #expect(cells.filter(\.isActive).map(\.day) == [1, 3])
        #expect(cells.filter(\.isToday).map(\.day) == [3])
    }

    @Test func touchingTheChartShowsThatWeeksValues() async throws {
        let repository = FakeProgressRepository()
        repository.results[.run] = .success(.fixture(sport: .run, thisWeekKm: 21))
        let store = makeStore(repository)
        await store.load(practicedSports: [.run])

        store.selectedDate = try #require(CalendarDay(year: 2026, month: 11, day: 5).startInParis)

        #expect(store.selectedWeek?.weekStart == CalendarDay(year: 2026, month: 11, day: 2))
        #expect(store.selectedWeek?.distance == Distance(meters: 21_000))
    }

    @Test func aFailureSaysSoAndCanBeRetried() async {
        let repository = FakeProgressRepository()
        repository.results[.run] = .failure(.offline)
        let store = makeStore(repository)

        await store.load(practicedSports: [.run])
        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))

        repository.results[.run] = .success(.fixture(sport: .run))
        await store.refresh()
        #expect(store.phase == .loaded)
        #expect(store.progress == .fixture(sport: .run))
    }

    @Test func signOutForgetsTheProgress() async {
        let repository = FakeProgressRepository()
        repository.results[.run] = .success(.fixture(sport: .run))
        let store = makeStore(repository)
        await store.load(practicedSports: [.run])

        store.reset()

        #expect(store.progress == nil)
        #expect(store.phase == .idle)
        #expect(store.sports.isEmpty)
        await store.refresh()
        #expect(repository.calls == [.run])
    }
}
