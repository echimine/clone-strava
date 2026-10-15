import Foundation
import Testing
@testable import StravaClone

/// Distance left on the followed Itinerary and its state, as the Recording screen shows them
/// (ADR-031 §6, §7, §8).
struct RecordingItineraryFormattersTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let line = SyntheticTrack.through([(0, 0), (1_000, 0)])

    /// The followed Itinerary after one fix every 5 s at `positions`.
    private func followed(after positions: [(east: Double, north: Double)], returnPath: ReturnPath? = nil) -> FollowedItinerary {
        var itinerary = FollowedItinerary(id: .fixture(1), name: "Tout droit", track: line, total: Distance(meters: 1_000), returnPath: returnPath)
        for (index, position) in positions.enumerated() {
            _ = itinerary.follow(LocationSample(
                coordinate: SyntheticTrack.point(east: position.east, north: position.north),
                altitude: nil,
                horizontalAccuracy: 5,
                timestamp: start.addingTimeInterval(Double(index) * 5)
            ))
        }
        return itinerary
    }

    @Test func beforeTheFirstSnapTheDistanceLeftIsADash() {
        let item = RecordingFormatters.itinerary(followed(after: []))

        #expect(item.value == "—")
        #expect(item.label == "Restant sur l'Itinéraire")
    }

    @Test func onTheTrackShowsTheDistanceLeft() {
        let item = RecordingFormatters.itinerary(followed(after: [(0, 0), (250, 0)]))

        #expect(item.value == "0,75")
        #expect(item.unit == "km")
        #expect(item.label == "Restant sur l'Itinéraire")
    }

    @Test func aMomentOffTheTrackOnlyFreezesTheValue() {
        let item = RecordingFormatters.itinerary(followed(after: [(0, 0), (250, 0), (250, 200)]))

        #expect(item.value == "0,75")
        #expect(item.label == "Restant sur l'Itinéraire")
    }

    @Test func offTheTrackFor3PointsAnd10SecondsTheStateReplacesTheLabel() {
        let item = RecordingFormatters.itinerary(followed(after: [(0, 0), (250, 0), (250, 200), (250, 210), (250, 220)]))

        #expect(item.value == "0,75")
        #expect(item.label == "Hors Itinéraire")
    }

    @Test func aReturnPathShowsCheminRecalculeAndTheDistanceLeftThroughIt() {
        let returnPath = ReturnPath(
            path: [SyntheticTrack.point(east: 250, north: 200), SyntheticTrack.point(east: 300, north: 0)],
            distance: Distance(meters: 240),
            returnPoint: ItineraryProgress.ReturnPoint(coordinate: SyntheticTrack.point(east: 300, north: 0), alongM: 300)
        )
        let item = RecordingFormatters.itinerary(followed(after: [(250, 200)], returnPath: returnPath))

        #expect(item.value == "0,94") // 240 m of Return path, then 700 m of Itinerary
        #expect(item.label == "Chemin recalculé")
    }

    @Test func theEndShowsZeroAndItineraryFinished() {
        let item = RecordingFormatters.itinerary(followed(after: [(0, 0), (500, 0), (995, 0)]))

        #expect(item.value == "0,00")
        #expect(item.label == "Itinéraire terminé")
    }
}
