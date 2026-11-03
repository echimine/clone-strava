import Foundation
import Testing
@testable import StravaClone

/// "Temps intermédiaires" (ADR-036 §9): one kilometre per row and the rest last, pace or
/// speed after the sport, a bar proportional to speed, the FC column only with heart rate.
struct ActivitySplitsTableTests {
    private func split(_ meters: Double, _ seconds: Int, elevation: Double? = nil, heartRate: Int? = nil) -> ActivitySplit {
        ActivitySplit(distance: Distance(meters: meters), movingTime: .seconds(seconds), elevationDiff: elevation, avgHeartRate: heartRate)
    }

    @Test func aRunHasOneRowPerKilometreAndTheRestLast() {
        let table = ActivitySplitsTable(
            splits: [
                split(1_000, 300, elevation: 4.4, heartRate: 150),
                split(1_000, 250, elevation: -3.6, heartRate: 162),
                split(140, 35, elevation: 0.2, heartRate: nil),
            ],
            sport: .run
        )

        #expect(table.speedTitle == "Allure")
        #expect(table.showsHeartRate)
        #expect(table.rows.map(\.kilometer) == ["1", "2", "0,14"])
        #expect(table.rows.map(\.speed) == ["5:00 /km", "4:10 /km", "4:10 /km"])
        #expect(table.rows.map(\.elevation) == ["+4 m", "-4 m", "0 m"])
        #expect(table.rows.map(\.heartRate) == ["150", "162", nil])
    }

    /// The fastest kilometre fills the bar; the others in proportion to their speed.
    @Test func barsAreProportionalToSpeed() {
        let table = ActivitySplitsTable(splits: [split(1_000, 400), split(1_000, 200), split(500, 0)], sport: .run)

        #expect(table.rows.map(\.barFraction) == [0.5, 1, 0])
        #expect(table.rows.last?.speed == "–")
    }

    @Test func aRideShowsSpeedAndHidesHeartRateWithoutIt() {
        let table = ActivitySplitsTable(splits: [split(1_000, 100), split(1_000, 125)], sport: .ride)

        #expect(table.speedTitle == "Vitesse")
        #expect(!table.showsHeartRate)
        #expect(table.rows.map(\.speed) == ["36,0 km/h", "28,8 km/h"])
        #expect(table.rows.map(\.elevation) == [nil, nil])
        #expect(table.rows.map(\.kilometer) == ["1", "2"])
    }
}
