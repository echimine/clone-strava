import Foundation

/// `APIClient` adapter of `AthleteStatsRepository`: `GET /v1/athletes/:id/stats?sport=`
/// (ADR-036 §4), decoded with the generated OpenAPI type (ADR-026).
struct APIAthleteStatsRepository: AthleteStatsRepository {
    private typealias StatsResponse = Components.Schemas.AthleteStatsResponseDto_Output

    let apiClient: APIClient

    func stats(of athleteId: String, sport: SportType?) async throws(AthleteError) -> AthleteStats {
        let query = sport.map { [URLQueryItem(name: "sport", value: $0.code)] } ?? []
        let response: StatsResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)/stats", query: query)
        }
        return response.model
    }
}

private extension Components.Schemas.AthleteStatsResponseDto_Output {
    var model: AthleteStats {
        AthleteStats(
            sport: sportTypeCode.map(SportType.init(code:)),
            recent: AthleteStats.Recent(
                activitiesPerWeek: recent.activitiesPerWeek,
                movingTimePerWeek: .seconds(recent.movingTimeSPerWeek),
                distancePerWeek: Distance(meters: recent.distanceMPerWeek)
            ),
            yearToDate: AthleteStats.YearToDate(
                activityCount: yearToDate.activityCount,
                movingTime: .seconds(yearToDate.movingTimeS),
                distance: Distance(meters: yearToDate.distanceM),
                elevationGain: yearToDate.elevationGainM
            ),
            allTime: AthleteStats.AllTime(
                activityCount: allTime.activityCount,
                distance: Distance(meters: allTime.distanceM),
                elevationGain: allTime.elevationGainM
            )
        )
    }
}
