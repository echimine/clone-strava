import Foundation

/// Which parts of the detail show (ADR-036 §9): the map when there is a route, and
/// sections 8 to 10 (splits, Allure, Fréquence cardiaque) only when the analysis has splits;
/// the charts need the series, and heart rate needs a heart rate. A manual Activity has none.
struct ActivityDetailSections: Hashable {
    let showsMap: Bool
    let splits: ActivitySplitsTable?
    let speedChart: ActivitySpeedChartData?
    let heartRateChart: ActivityHeartRateChartData?

    init(detail: ActivityDetail) {
        showsMap = detail.route != nil
        guard let analysis = detail.analysis, !analysis.splits.isEmpty else {
            splits = nil
            speedChart = nil
            heartRateChart = nil
            return
        }
        splits = ActivitySplitsTable(splits: analysis.splits, sport: detail.sport)
        speedChart = analysis.series.map { ActivitySpeedChartData(series: $0, sport: detail.sport) }
        heartRateChart = analysis.series.flatMap(ActivityHeartRateChartData.init(series:))
    }
}
