import Foundation
import Testing
@testable import StravaClone

/// What the Live Activity shows at once rather than at the next 5 s update (ADR-031 §9).
struct RecordingLiveActivityContentTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let square = SyntheticTrack.through([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)])
    private let returnPoint = ItineraryProgress.ReturnPoint(coordinate: SyntheticTrack.point(east: 400, north: 200), alongM: 600)

    private func content(returnPath: ReturnPath?) -> RecordingLiveActivityContent {
        let itinerary = FollowedItinerary(
            id: .fixture(3),
            name: "Boucle",
            track: square,
            total: Distance(meters: 1_600),
            returnPath: returnPath
        )
        let snapshot = RecordingSnapshot(recording: Recording(sport: .run, startedAt: start), itinerary: itinerary)
        return RecordingLiveActivityContent(snapshot, at: start.addingTimeInterval(60))
    }

    private func path(via east: Double) -> ReturnPath {
        ReturnPath(
            path: [SyntheticTrack.point(east: 200, north: 200), SyntheticTrack.point(east: east, north: 250), returnPoint.coordinate],
            distance: Distance(meters: 260),
            returnPoint: returnPoint
        )
    }

    @Test func aReturnPathReplacingAnotherShowsAtOnceEvenToTheSameReturnPoint() {
        let previous = content(returnPath: path(via: 300))

        #expect(content(returnPath: path(via: 320)).needsImmediateUpdate(after: previous))
    }

    @Test func theSameReturnPathWaitsForTheNextUpdate() {
        let previous = content(returnPath: path(via: 300))

        #expect(!content(returnPath: path(via: 300)).needsImmediateUpdate(after: previous))
    }

    @Test func aReturnPathArrivingOrDisappearingShowsAtOnce() {
        #expect(content(returnPath: path(via: 300)).needsImmediateUpdate(after: content(returnPath: nil)))
        #expect(content(returnPath: nil).needsImmediateUpdate(after: content(returnPath: path(via: 300))))
    }
}
