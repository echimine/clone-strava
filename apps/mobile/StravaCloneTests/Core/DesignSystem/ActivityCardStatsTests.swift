import Foundation
import Testing
@testable import StravaClone

/// The card's three stats depend on the sport's `paceUnit` (ADR-036 §5).
struct ActivityCardStatsTests {
    @Test func aRunShowsDistancePaceAndTime() {
        let post = ActivityPost.fixture(sport: .run, elevationGain: 120, avgSpeedMs: 1_000.0 / 330)

        #expect(ActivityCardStat.stats(for: post) == [
            ActivityCardStat(label: "Distance", value: "10,00 km"),
            ActivityCardStat(label: "Allure", value: "5:30 /km"),
            ActivityCardStat(label: "Temps", value: "50 min 0 s"),
        ])
    }

    @Test func aRideShowsDistanceElevationAndTime() {
        let post = ActivityPost.fixture(sport: .ride, elevationGain: 245.4, avgSpeedMs: 8)

        #expect(ActivityCardStat.stats(for: post) == [
            ActivityCardStat(label: "Distance", value: "10,00 km"),
            ActivityCardStat(label: "Dénivelé", value: "245 m"),
            ActivityCardStat(label: "Temps", value: "50 min 0 s"),
        ])
    }

    @Test func aMissingValueShowsADash() {
        let walk = ActivityPost.fixture(sport: .walk, avgSpeedMs: nil)
        let ride = ActivityPost.fixture(sport: .ride, elevationGain: nil)

        #expect(ActivityCardStat.stats(for: walk)[1] == ActivityCardStat(label: "Allure", value: "–"))
        #expect(ActivityCardStat.stats(for: ride)[1] == ActivityCardStat(label: "Dénivelé", value: "–"))
    }
}
