import Foundation
import Testing
@testable import StravaClone

/// What the Allure (Vitesse) chart plots (ADR-036 §9): pace with faster higher, or speed,
/// against the distance, over the altitude scaled into the bottom of the plot.
struct ActivitySpeedChartDataTests {
    /// Pace is plotted negated so faster is higher; a stop sits at the slowest pace.
    @Test func aRunPlotsPaceFasterHigher() {
        let series = ActivitySeries(distanceM: [0, 500, 1_000], speedMs: [1_000.0 / 300, 4, 0], altitudeM: [100, 150, 200], heartRateBpm: nil)

        let chart = ActivitySpeedChartData(series: series, sport: .run)

        #expect(chart.isPace)
        #expect(chart.points.map(\.kilometers) == [0, 0.5, 1])
        #expect(chart.points.map(\.value) == [-300, -250, -300])
        #expect(chart.domain == -305 ... -245)
        #expect(chart.axisLabel(-250) == "4:10")
    }

    /// The altitude fills the bottom 40 % of the plot, from its lowest to its highest point.
    @Test func altitudeIsScaledIntoTheBottomOfThePlot() {
        let series = ActivitySeries(distanceM: [0, 500, 1_000], speedMs: [1_000.0 / 300, 4, 0], altitudeM: [100, 150, 200], heartRateBpm: nil)

        let chart = ActivitySpeedChartData(series: series, sport: .run)

        #expect(chart.altitude.map(\.value) == [-305, -293, -281])
    }

    /// A crawl does not flatten the chart: pace is capped at 1.5 × the median.
    @Test func slowOutliersAreCapped() {
        let pace300 = 1_000.0 / 300
        let series = ActivitySeries(distanceM: [0, 1, 2, 3], speedMs: [pace300, pace300, pace300, 0.2], altitudeM: nil, heartRateBpm: nil)

        let chart = ActivitySpeedChartData(series: series, sport: .run)

        #expect(chart.points.map(\.value) == [-300, -300, -300, -450])
        #expect(chart.altitude.isEmpty)
    }

    @Test func aRidePlotsSpeedInKilometresPerHour() {
        let series = ActivitySeries(distanceM: [0, 2_000], speedMs: [10, 5], altitudeM: nil, heartRateBpm: nil)

        let chart = ActivitySpeedChartData(series: series, sport: .ride)

        #expect(!chart.isPace)
        #expect(chart.points.map(\.value) == [36, 18])
        #expect(chart.domain.lowerBound == 0)
        #expect(chart.domain.upperBound >= 36)
        #expect(chart.axisLabel(36) == "36 km/h")
    }
}
