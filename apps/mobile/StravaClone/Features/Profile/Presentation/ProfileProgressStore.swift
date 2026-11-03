import Foundation
import Observation

/// The Progrès tab (ADR-036 §4): sport pills that filter the whole tab, "Cette semaine", the
/// 12-week chart with its touched week, and the Série card. Owned by `ProfileStore`, reset at
/// sign-out.
@Observable
@MainActor
final class ProfileProgressStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    /// The pills: my practiced sports, else the active ones.
    private(set) var sports: [SportType] = []
    private(set) var sport: SportType?
    private(set) var progress: AthleteProgress?
    private(set) var phase: Phase = .idle
    /// The chart's `chartXSelection`: where the finger is.
    var selectedDate: Date?

    @ObservationIgnored private let loadProgress: LoadProgress
    @ObservationIgnored private let today: @Sendable () -> CalendarDay
    @ObservationIgnored private var generation = 0

    init(loadProgress: LoadProgress, today: @escaping @Sendable () -> CalendarDay = { ProgressCalendar.today() }) {
        self.loadProgress = loadProgress
        self.today = today
    }

    /// The week under the finger, whose values replace "Cette semaine"'s under the chart.
    var selectedWeek: WeekProgress? {
        selectedDate.flatMap { progress?.week(containing: $0) }
    }

    /// The Série card's calendar.
    var month: StreakMonth? {
        progress.map { StreakMonth(today: today(), activeDays: $0.activeDays) }
    }

    /// The tab appears: loads my first sport once, or again if my sports changed.
    func load(practicedSports: [SportType]) async {
        let offered = practicedSports.isEmpty ? SportType.active : practicedSports
        guard offered != sports || phase == .idle else { return }
        sports = offered
        if sport.map(offered.contains) != true {
            sport = offered.first
        }
        await refresh()
    }

    /// A pill: the whole tab for that sport.
    func select(_ sport: SportType) async {
        guard sport != self.sport else { return }
        self.sport = sport
        selectedDate = nil
        await refresh()
    }

    /// Pull-to-refresh, "Réessayer", and a new pill.
    func refresh() async {
        guard let sport else { return }
        generation += 1
        let current = generation
        phase = .loading
        do {
            let loaded = try await loadProgress(sport: sport)
            guard current == generation else { return }
            progress = loaded
            phase = .loaded
        } catch {
            guard current == generation else { return }
            progress = nil
            phase = .failed(message: StatisticsMessages.message(for: error))
        }
    }

    /// Sign-out: forgets the previous account's progress.
    func reset() {
        generation += 1
        sports = []
        sport = nil
        progress = nil
        phase = .idle
        selectedDate = nil
    }
}
