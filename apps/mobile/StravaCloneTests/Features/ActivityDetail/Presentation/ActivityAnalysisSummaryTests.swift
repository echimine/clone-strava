import Foundation
import Testing
@testable import StravaClone

/// The summary rows under the Allure (Vitesse) and Fréquence cardiaque charts (ADR-036 §9),
/// derived from the stats and the splits.
struct ActivityAnalysisSummaryTests {
    private func split(_ meters: Double, _ seconds: Int) -> ActivitySplit {
        ActivitySplit(distance: Distance(meters: meters), movingTime: .seconds(seconds), elevationDiff: nil, avgHeartRate: nil)
    }

    private func shown(_ items: [ActivityStatItem]) -> [String] {
        items.map { "\($0.label): \($0.value)" }
    }

    /// The rest of the distance (140 m in 30 s, faster) is not a split to beat.
    @Test func aRunShowsMovingPaceMovingTimePaceOverElapsedTimeElapsedTimeAndFastestSplit() {
        let stats = ActivityStats.fixture(distanceM: 10_000, movingTimeS: 3_000, elapsedTimeS: 3_200, avgSpeedMs: 10_000.0 / 3_000.0)
        let splits = [split(1_000, 300), split(1_000, 280), split(1_000, 310), split(140, 30)]

        #expect(shown(ActivityAnalysisSummary.speedRows(stats: stats, splits: splits, sport: .run)) == [
            "Allure moyenne: 5:00 /km",
            "Durée de déplacement: 50 min 0 s",
            "Allure sur le temps écoulé: 5:20 /km",
            "Temps écoulé: 53 min 20 s",
            "Split le plus rapide: 4:40 /km",
        ])
    }

    @Test func aRideShowsSpeeds() {
        let stats = ActivityStats.fixture(distanceM: 40_000, movingTimeS: 4_000, elapsedTimeS: 5_000, avgSpeedMs: 10)
        let splits = [split(1_000, 100), split(1_000, 80)]

        #expect(shown(ActivityAnalysisSummary.speedRows(stats: stats, splits: splits, sport: .ride)) == [
            "Vitesse moyenne: 36,0 km/h",
            "Durée de déplacement: 1 h 06 min",
            "Vitesse sur le temps écoulé: 28,8 km/h",
            "Temps écoulé: 1 h 23 min",
            "Split le plus rapide: 45,0 km/h",
        ])
    }

    /// Unmeasured values are left out; a single split shorter than a kilometre is no fastest split.
    @Test func missingValuesAreHidden() {
        let stats = ActivityStats.fixture(distanceM: 800, movingTimeS: 240, elapsedTimeS: nil, avgSpeedMs: 800.0 / 240.0)

        #expect(shown(ActivityAnalysisSummary.speedRows(stats: stats, splits: [split(800, 240)], sport: .run)) == [
            "Allure moyenne: 5:00 /km",
            "Durée de déplacement: 4 min 0 s",
        ])
    }

    @Test func heartRateRowsComeFromTheStats() {
        let stats = ActivityStats.fixture(avgHeartRate: 152, maxHeartRate: 181)

        #expect(shown(ActivityAnalysisSummary.heartRateRows(stats: stats, series: nil)) == [
            "FC moyenne: 152 bpm",
            "FC max: 181 bpm",
        ])
    }

    /// Without heart rate in the stats, the series gives them (0 is a missing sample).
    @Test func heartRateRowsFallBackOnTheSeries() {
        let series = ActivitySeries(distanceM: [0, 10, 20, 30], speedMs: [3, 3, 3, 3], altitudeM: nil, heartRateBpm: [140, 0, 150, 160])

        #expect(shown(ActivityAnalysisSummary.heartRateRows(stats: .fixture(), series: series)) == [
            "FC moyenne: 150 bpm",
            "FC max: 160 bpm",
        ])
    }
}
