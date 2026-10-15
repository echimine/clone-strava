import Foundation
import Testing
@testable import StravaClone

/// Distance left on the followed Itinerary and its state, as the Recording screen shows them
/// (ADR-031 §6, §8).
struct RecordingItineraryFormattersTests {
    private let line = SyntheticTrack.through([(0, 0), (1_000, 0)])

    private func progress(after positions: [(east: Double, north: Double)]) -> ItineraryProgress {
        var progress = ItineraryProgress(track: line, total: Distance(meters: 1_000))
        for position in positions {
            progress.update(with: LocationSample(
                coordinate: SyntheticTrack.point(east: position.east, north: position.north),
                altitude: nil,
                horizontalAccuracy: 5,
                timestamp: Date()
            ))
        }
        return progress
    }

    @Test func beforeTheFirstSnapTheDistanceLeftIsADash() {
        let item = RecordingFormatters.itinerary(progress(after: []))

        #expect(item.value == "—")
        #expect(item.label == "Restant sur l'Itinéraire")
    }

    @Test func onTheTrackShowsTheDistanceLeft() {
        let item = RecordingFormatters.itinerary(progress(after: [(0, 0), (250, 0)]))

        #expect(item.value == "0,75")
        #expect(item.unit == "km")
        #expect(item.label == "Restant sur l'Itinéraire")
    }

    @Test func offTheTrackTheStateReplacesTheLabel() {
        let item = RecordingFormatters.itinerary(progress(after: [(0, 0), (250, 0), (250, 200)]))

        #expect(item.value == "0,75")
        #expect(item.label == "Hors Itinéraire")
    }

    @Test func theEndShowsZeroAndItineraryFinished() {
        let item = RecordingFormatters.itinerary(progress(after: [(0, 0), (500, 0), (995, 0)]))

        #expect(item.value == "0,00")
        #expect(item.label == "Itinéraire terminé")
    }
}
