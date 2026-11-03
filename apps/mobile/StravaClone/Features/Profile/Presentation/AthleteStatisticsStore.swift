import Foundation
import Observation

/// The Statistiques screen (ADR-036 §4) of any athlete: a sport picker, then ACTIVITÉ, DEPUIS
/// LE DÉBUT DE L'ANNÉE and DE TOUT TEMPS for that sport. One per screen.
@Observable
@MainActor
final class AthleteStatisticsStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    let athleteId: String
    /// The picker's sports: the athlete's practiced sports, else the active ones.
    let sports: [SportType]
    private(set) var sport: SportType
    private(set) var stats: AthleteStats?
    private(set) var phase: Phase = .idle

    @ObservationIgnored private let loadStats: LoadAthleteStats
    @ObservationIgnored private var generation = 0

    init(request: AthleteStatisticsRequest, loadStats: LoadAthleteStats) {
        athleteId = request.athleteId
        sports = request.sports.isEmpty ? SportType.active : request.sports
        sport = sports[0]
        self.loadStats = loadStats
    }

    /// First appearance: loads once.
    func load() async {
        guard phase == .idle else { return }
        await reload()
    }

    /// The picker: the screen shows that sport's statistics.
    func select(_ sport: SportType) async {
        guard sport != self.sport || stats == nil else { return }
        self.sport = sport
        await reload()
    }

    func retry() async {
        await reload()
    }

    private func reload() async {
        generation += 1
        let current = generation
        phase = .loading
        do {
            let loaded = try await loadStats(athleteId: athleteId, sport: sport)
            guard current == generation else { return }
            stats = loaded
            phase = .loaded
        } catch {
            guard current == generation else { return }
            stats = nil
            phase = .failed(message: ProfileMessages.message(for: error))
        }
    }
}

/// One grey uppercase section of the Statistiques list (ADR-036 §4), ready to display.
struct AthleteStatisticsSection: Equatable, Identifiable {
    struct Row: Equatable {
        let label: String
        let value: String
    }

    let title: String
    let rows: [Row]

    var id: String { title }

    static func sections(for stats: AthleteStats) -> [AthleteStatisticsSection] {
        let outings = StatisticsMessages.outings(stats.sport)
        let showsElevation = stats.sport?.tracksElevation ?? true
        func elevation(_ meters: Double) -> [Row] {
            showsElevation ? [Row(label: StatisticsMessages.elevation, value: ActivityFormatters.elevation(meters))] : []
        }
        return [
            AthleteStatisticsSection(title: StatisticsMessages.recentTitle, rows: [
                Row(label: StatisticsMessages.perWeek(outings), value: StatisticsMessages.average(stats.recent.activitiesPerWeek)),
                Row(label: StatisticsMessages.perWeek(StatisticsMessages.time), value: ActivityFormatters.duration(stats.recent.movingTimePerWeek)),
                Row(label: StatisticsMessages.perWeek(StatisticsMessages.distance), value: ActivityFormatters.distance(stats.recent.distancePerWeek)),
            ]),
            AthleteStatisticsSection(title: StatisticsMessages.yearToDateTitle, rows: [
                Row(label: outings, value: "\(stats.yearToDate.activityCount)"),
                Row(label: StatisticsMessages.time, value: ActivityFormatters.duration(stats.yearToDate.movingTime)),
                Row(label: StatisticsMessages.distance, value: ActivityFormatters.distance(stats.yearToDate.distance)),
            ] + elevation(stats.yearToDate.elevationGain)),
            AthleteStatisticsSection(title: StatisticsMessages.allTimeTitle, rows: [
                Row(label: outings, value: "\(stats.allTime.activityCount)"),
                Row(label: StatisticsMessages.distance, value: ActivityFormatters.distance(stats.allTime.distance)),
            ] + elevation(stats.allTime.elevationGain)),
        ]
    }
}
