import Foundation
import Testing
@testable import StravaClone

/// The detail's stats grid (ADR-033 §3): a stat shows only when it is not null and the sport
/// tracks it; pace or speed follows the sport; heart rate and calories only when present.
struct ActivityStatItemsTests {
    private func shown(_ stats: ActivityStats, _ sport: SportType) -> [String] {
        ActivityStatItem.items(for: stats, sport: sport).map { "\($0.label): \($0.value)" }
    }

    @Test func aRunShowsItsPaceAndEveryMeasuredValue() {
        let stats = ActivityStats.fixture(
            distanceM: 10_000,
            movingTimeS: 3_000,
            elapsedTimeS: 3_200,
            elevationGainM: 120,
            avgSpeedMs: 10_000.0 / 3_000.0,
            maxSpeedMs: 5,
            avgHeartRate: 150,
            maxHeartRate: 181,
            calories: 640
        )

        #expect(shown(stats, .run) == [
            "Distance: 10,00 km",
            "Allure moy.: 5:00 /km",
            "Temps: 50 min 0 s",
            "Temps écoulé: 53 min 20 s",
            "Dénivelé: 120 m",
            "Allure max: 3:20 /km",
            "FC moy.: 150 bpm",
            "FC max: 181 bpm",
            "Calories: 640 kcal",
        ])
    }

    @Test func aRideShowsItsSpeed() {
        let stats = ActivityStats.fixture(avgSpeedMs: 10, maxSpeedMs: 15)

        let items = shown(stats, .ride)

        #expect(items.contains("Vitesse moy.: 36,0 km/h"))
        #expect(items.contains("Vitesse max: 54,0 km/h"))
        #expect(!items.contains { $0.hasPrefix("Allure") })
    }

    @Test func nullValuesAreHidden() {
        let stats = ActivityStats.fixture(
            distanceM: 10_000,
            movingTimeS: 3_000,
            elapsedTimeS: nil,
            elevationGainM: nil,
            avgSpeedMs: nil,
            maxSpeedMs: nil
        )

        #expect(shown(stats, .run) == ["Distance: 10,00 km", "Temps: 50 min 0 s"])
    }

    /// A swim does not track elevation (`sports.sport_type`, ADR-017): a value sent anyway is
    /// not shown.
    @Test func aStatTheSportDoesNotTrackIsHiddenEvenWhenPresent() {
        let stats = ActivityStats.fixture(elevationGainM: 35)

        #expect(!shown(stats, .swim).contains { $0.hasPrefix("Dénivelé") })
        #expect(shown(stats, .hike).contains("Dénivelé: 35 m"))
    }

    /// A zero speed has no pace.
    @Test func aStillActivityHasNoPace() {
        let stats = ActivityStats.fixture(avgSpeedMs: 0, maxSpeedMs: 0)

        #expect(!shown(stats, .walk).contains { $0.hasPrefix("Allure") })
    }
}
