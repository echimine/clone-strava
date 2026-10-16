import Foundation
import Testing
@testable import StravaClone

/// ADR-032 §5: the finish screen's stats count up to their final values, in the formats of the
/// Recording screen (ADR-031 §5). The current speed is not a finish stat.
struct FinishStatsCountUpTests {
    private let run = RecordingStats(sport: .run, elapsed: .seconds(1_500), distance: Distance(meters: 5_000), currentSpeedMs: 3)
    private let ride = RecordingStats(sport: .ride, elapsed: .seconds(3_600), distance: Distance(meters: 24_000), currentSpeedMs: 7)

    @Test func atTheEndTheValuesAreTheFinalOnesInFrench() {
        let items = FinishStatsCountUp.items(run, progress: 1)

        #expect(items.map(\.label) == ["Temps", "Distance", "Allure moy."])
        #expect(items.map(\.value) == ["0:25:00", "5,00", "5:00"])
        #expect(items.map(\.unit) == ["", "km", "/km"])
    }

    @Test func onABikeTheFinalValuesLeaveOutTheCurrentSpeed() {
        let items = FinishStatsCountUp.items(ride, progress: 1)

        #expect(items.map(\.label) == ["Temps", "Distance", "Vitesse moy."])
        #expect(items.map(\.value) == ["1:00:00", "24,00", "24,0"])
    }

    @Test func halfwayEachValueIsHalfItsFinalValue() {
        #expect(FinishStatsCountUp.items(run, progress: 0.5).map(\.value) == ["0:12:30", "2,50", "2:30"])
        #expect(FinishStatsCountUp.items(ride, progress: 0.5).map(\.value) == ["0:30:00", "12,00", "12,0"])
    }

    @Test func theCountStartsFromZero() {
        #expect(FinishStatsCountUp.items(run, progress: 0).map(\.value) == ["0:00:00", "0,00", "0:00"])
        #expect(FinishStatsCountUp.items(ride, progress: 0).map(\.value) == ["0:00:00", "0,00", "0,0"])
    }

    /// Truncated like the live distance: 4,996 km never shows 5,00 before the end.
    @Test func theDistanceNeverRoundsUpPastWhatWasCovered() {
        let stats = RecordingStats(sport: .run, elapsed: .seconds(1_500), distance: Distance(meters: 4_996), currentSpeedMs: nil)

        #expect(FinishStatsCountUp.items(stats, progress: 0.999).map(\.value)[1] == "4,99")
        #expect(FinishStatsCountUp.items(stats, progress: 1).map(\.value)[1] == "4,99")
    }

    @Test func aPaceWithoutMeaningStaysADash() {
        let stats = RecordingStats(sport: .walk, elapsed: .seconds(20), distance: Distance(meters: 50), currentSpeedMs: nil)

        #expect(FinishStatsCountUp.items(stats, progress: 0.5).map(\.value)[2] == "–")
        #expect(FinishStatsCountUp.items(stats, progress: 1).map(\.value)[2] == "–")
    }
}
