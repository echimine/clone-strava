import Foundation
import Testing
@testable import StravaClone

/// What the ActivityKit adapter hands the widget extension (ADR-031 §9): plain values only.
struct ActivityKitRecordingLiveActivityTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)

    private func point(_ seconds: TimeInterval, north: Double) -> LocationSample {
        LocationSample(
            coordinate: origin.offset(northMeters: north),
            altitude: nil,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    /// A run of 300 m in 2 min, then a Pause, with an Itinerary not reached yet.
    private var content: RecordingLiveActivityContent {
        var recording = Recording(sport: .run, startedAt: start)
        recording.pause(at: start.addingTimeInterval(120))
        let track = SyntheticTrack.through([(5_000, 0), (5_000, 1_000)])
        let itinerary = FollowedItinerary(id: .fixture(1), name: "Les quais", track: track, total: Distance(meters: 1_000))
        let snapshot = RecordingSnapshot(
            recording: recording,
            points: [point(0, north: 0), point(120, north: 300)],
            itinerary: itinerary
        )
        return RecordingLiveActivityContent(snapshot, at: start.addingTimeInterval(200))
    }

    @Test func theSportIsFixedInTheAttributes() {
        let attributes = RecordingActivityAttributes(content)

        #expect(attributes.sportName == "Course à pied")
        #expect(attributes.sportSymbol == "figure.run")
        #expect(attributes.showsPace)
    }

    @Test func theStateCarriesTheTimerDatesAndTheStats() {
        let state = RecordingActivityAttributes.ContentState(content)

        #expect(state.timerStart == start)
        #expect(state.pausedAt == start.addingTimeInterval(120))
        #expect(abs(state.distanceM - 300) < 0.01)
        #expect(state.averagePaceS == 400) // 2 min for 0.3 km
        #expect(state.currentSpeedKmh == nil)
        #expect(state.isSaved == false)
        #expect(state.itinerary == RecordingActivityAttributes.Itinerary(
            name: "Les quais",
            remainingM: nil,
            fraction: 0,
            state: .notSnapped
        ))
    }
}
