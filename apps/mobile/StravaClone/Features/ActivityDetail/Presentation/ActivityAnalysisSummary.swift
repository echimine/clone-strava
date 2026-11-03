import Foundation

/// The summary rows under the detail's charts (ADR-036 §6, §9), derived by the app from the
/// official stats and the splits. A value that was not measured is left out.
enum ActivityAnalysisSummary {
    /// Under Allure (Vitesse): the moving pace, the moving time, the pace over the elapsed
    /// time, the elapsed time and the fastest full kilometre.
    static func speedRows(stats: ActivityStats?, splits: [ActivitySplit], sport: SportType) -> [ActivityStatItem] {
        let pace = sport.paceUnit == .pace
        var rows: [ActivityStatItem] = []
        func add(_ label: String, _ value: String?) {
            if let value { rows.append(ActivityStatItem(label: label, value: value)) }
        }
        add(
            ActivityAnalysisMessages.averageSpeed(pace: pace),
            stats?.avgSpeedMs.flatMap { ActivitySplitsTable.speedText($0, pace: pace) }
        )
        add(ActivityAnalysisMessages.movingTime, stats?.movingTime.map(ActivityFormatters.duration))
        add(
            ActivityAnalysisMessages.elapsedSpeed(pace: pace),
            elapsedSpeed(stats).flatMap { ActivitySplitsTable.speedText($0, pace: pace) }
        )
        add(ActivityAnalysisMessages.elapsedTime, stats?.elapsedTime.map(ActivityFormatters.duration))
        add(ActivityAnalysisMessages.fastestSplit, fastestSplitSpeed(splits).flatMap { ActivitySplitsTable.speedText($0, pace: pace) })
        return rows
    }

    /// Under Fréquence cardiaque: FC moyenne and FC max, from the stats or else from the series.
    static func heartRateRows(stats: ActivityStats?, series: ActivitySeries?) -> [ActivityStatItem] {
        let samples = series?.heartRateBpm?.filter { $0 > 0 } ?? []
        let average = stats?.avgHeartRate
            ?? (samples.isEmpty ? nil : Int((Double(samples.reduce(0, +)) / Double(samples.count)).rounded()))
        let max = stats?.maxHeartRate ?? samples.max()
        return [
            average.map { ActivityStatItem(label: ActivityAnalysisMessages.averageHeartRate, value: ActivityAnalysisMessages.bpm($0)) },
            max.map { ActivityStatItem(label: ActivityAnalysisMessages.maxHeartRate, value: ActivityAnalysisMessages.bpm($0)) },
        ].compactMap(\.self)
    }

    private static func elapsedSpeed(_ stats: ActivityStats?) -> Double? {
        guard let distance = stats?.distance, let elapsed = stats?.elapsedTime else { return nil }
        let seconds = Double(elapsed.components.seconds)
        return seconds > 0 ? distance.meters / seconds : nil
    }

    /// The rest of the distance, shorter than a kilometre, is not a split to beat.
    private static func fastestSplitSpeed(_ splits: [ActivitySplit]) -> Double? {
        splits.filter { $0.distance.meters >= ActivitySplitsTable.fullSplitMeters }.compactMap(\.speedMs).max()
    }
}
