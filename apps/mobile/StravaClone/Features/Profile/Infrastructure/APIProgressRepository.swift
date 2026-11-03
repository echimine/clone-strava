import Foundation

/// `APIClient` adapter of `ProgressRepository`: `GET /v1/me/progress?sport=` (ADR-036 §4),
/// decoded with the generated OpenAPI type (ADR-026).
struct APIProgressRepository: ProgressRepository {
    private typealias ProgressResponse = Components.Schemas.ProgressResponseDto_Output

    let apiClient: APIClient

    func progress(sport: SportType) async throws(AthleteError) -> AthleteProgress {
        let response: ProgressResponse = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/me/progress", query: [URLQueryItem(name: "sport", value: sport.code)])
        }
        return response.model
    }
}

private extension Components.Schemas.ProgressResponseDto_Output {
    var model: AthleteProgress {
        AthleteProgress(
            sport: SportType(code: sportTypeCode),
            weeks: weeks.compactMap { week in
                CalendarDay(iso: week.weekStart).map {
                    WeekProgress(
                        weekStart: $0,
                        distance: Distance(meters: week.distanceM),
                        elevationGain: week.elevationGainM,
                        movingTime: .seconds(week.movingTimeS),
                        activityCount: week.activityCount
                    )
                }
            },
            streakWeeks: streak.weeks,
            activeDays: Set(streak.activeDays.compactMap(CalendarDay.init(iso:)))
        )
    }
}
