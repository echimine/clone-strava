import Foundation

/// An athlete's Statistiques (ADR-036 §4), for one sport or all of them: only the Activities
/// this viewer may see count.
struct AthleteStats: Equatable, Sendable {
    /// ACTIVITÉ: the averages over the 4 full weeks before the current one.
    struct Recent: Equatable, Sendable {
        let activitiesPerWeek: Double
        let movingTimePerWeek: Duration
        let distancePerWeek: Distance
    }

    /// DEPUIS LE DÉBUT DE L'ANNÉE: since 1 January, Europe/Paris.
    struct YearToDate: Equatable, Sendable {
        let activityCount: Int
        let movingTime: Duration
        let distance: Distance
        let elevationGain: Double
    }

    /// DE TOUT TEMPS.
    struct AllTime: Equatable, Sendable {
        let activityCount: Int
        let distance: Distance
        let elevationGain: Double
    }

    /// Nil for all sports.
    let sport: SportType?
    let recent: Recent
    let yearToDate: YearToDate
    let allTime: AllTime
}

/// Reads any athlete's Statistiques (`GET /v1/athletes/:id/stats`, ADR-036 §4). Implemented over
/// the API in `Core/Athletes`, faked in tests. Shared by my profile and another athlete's.
protocol AthleteStatsRepository: Sendable {
    /// `sport` nil: all sports.
    func stats(of athleteId: String, sport: SportType?) async throws(AthleteError) -> AthleteStats
}
