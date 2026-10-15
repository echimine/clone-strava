import Foundation
import Testing
@testable import StravaClone

struct RecordingFormattersTests {
    @Test func timerIsHoursMinutesSeconds() {
        #expect(RecordingFormatters.timer(.zero) == "0:00:00")
        #expect(RecordingFormatters.timer(.seconds(312)) == "0:05:12")
        #expect(RecordingFormatters.timer(.milliseconds(3_725_900)) == "1:02:05")
    }

    /// Truncated: the live distance never shows more than was covered (4,996 km is not 5,00).
    @Test func distanceIsTruncatedKilometersWithAFrenchComma() {
        #expect(RecordingFormatters.distance(.zero) == "0,00")
        #expect(RecordingFormatters.distance(Distance(meters: 12_349)) == "12,34")
        #expect(RecordingFormatters.distance(Distance(meters: 4_996)) == "4,99")
    }

    @Test func paceIsMinutesSecondsOrADash() {
        #expect(RecordingFormatters.pace(.seconds(312)) == "5:12")
        #expect(RecordingFormatters.pace(.milliseconds(299_600)) == "5:00")
        #expect(RecordingFormatters.pace(nil) == "–")
    }

    @Test func speedIsKilometersPerHourWithOneDecimalOrADash() {
        #expect(RecordingFormatters.speed(6.75) == "24,3")
        #expect(RecordingFormatters.speed(0) == "0,0")
        #expect(RecordingFormatters.speed(nil) == "–")
    }

    @Test func onFootShowsTheAveragePace() {
        let stats = RecordingStats(sport: .run, elapsed: .seconds(312), distance: Distance(meters: 1_000), currentSpeedMs: 3)

        let items = RecordingFormatters.items(stats)

        #expect(items.map(\.label) == ["Temps", "Distance", "Allure moy."])
        #expect(items.map(\.value) == ["0:05:12", "1,00", "5:12"])
        #expect(items.map(\.unit) == ["", "km", "/km"])
    }

    @Test func onABikeShowsCurrentAndAverageSpeed() {
        let stats = RecordingStats(sport: .ride, elapsed: .seconds(3_600), distance: Distance(meters: 24_300), currentSpeedMs: nil)

        let items = RecordingFormatters.items(stats)

        #expect(items.map(\.label) == ["Temps", "Distance", "Vitesse", "Vitesse moy."])
        #expect(items.map(\.value) == ["1:00:00", "24,30", "–", "24,3"])
    }
}
