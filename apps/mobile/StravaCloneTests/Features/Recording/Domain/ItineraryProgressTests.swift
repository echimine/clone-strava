import Foundation
import Testing
@testable import StravaClone

/// Progress along a followed Itinerary on synthetic tracks (ADR-031 §6).
struct ItineraryProgressTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    /// A 400 m square, start = finish at the south-west corner, anticlockwise: east, north, west, south.
    private let loop = SyntheticTrack.through([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)])

    private func fix(east: Double, north: Double, accuracy: Double = 5, at seconds: TimeInterval = 0) -> LocationSample {
        LocationSample(
            coordinate: SyntheticTrack.point(east: east, north: north),
            altitude: nil,
            horizontalAccuracy: accuracy,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    private func remaining(_ progress: ItineraryProgress) -> Double? {
        progress.remaining?.meters
    }

    @Test func aLoopShowsItsFullDistanceAtTheStartAndEndsFinished() {
        var progress = ItineraryProgress(track: loop, total: Distance(meters: 1_600))

        progress.update(with: fix(east: 0, north: 4))
        #expect(progress.status == .onTrack)
        #expect(abs(remaining(progress)! - 1_600) < 2)

        progress.update(with: fix(east: 200, north: 3))
        #expect(abs(remaining(progress)! - 1_400) < 2)
        progress.update(with: fix(east: 400, north: 200))
        #expect(abs(remaining(progress)! - 1_000) < 2)
        progress.update(with: fix(east: 200, north: 400))
        progress.update(with: fix(east: 0, north: 400))
        progress.update(with: fix(east: 2, north: 200))
        #expect(abs(remaining(progress)! - 200) < 3)
        progress.update(with: fix(east: 0, north: 5))

        #expect(progress.status == .finished)
        #expect(progress.remaining == .zero)
        #expect(progress.fraction == 1)
    }

    @Test func nothingIsShownBeforeTheFirstPositionWithin50MetersOfTheTrack() {
        var progress = ItineraryProgress(track: loop, total: Distance(meters: 1_600))

        progress.update(with: fix(east: 200, north: -60))

        #expect(progress.status == .notSnapped)
        #expect(progress.remaining == nil)
        #expect(progress.saved.hasSnapped == false)
    }

    @Test func anOutAndBackCountsTheWayBackAfterTheWayOut() {
        let line = SyntheticTrack.through([(0, 0), (1_000, 0), (0, 0)])
        var progress = ItineraryProgress(track: line, total: Distance(meters: 2_000))

        // Every 10 m out, then back: the way out and the way back lie on the same road.
        for east in stride(from: 0.0, through: 1_000, by: 10) {
            progress.update(with: fix(east: east, north: 2))
        }
        #expect(abs(remaining(progress)! - 1_000) < 2)
        for east in stride(from: 1_000.0, through: 500, by: -10) {
            progress.update(with: fix(east: east, north: -2))
        }

        #expect(progress.status == .onTrack)
        #expect(abs(remaining(progress)! - 500) < 2)
    }

    @Test func startingHalfwayShowsWhatIsLeftFromThere() {
        let line = SyntheticTrack.through([(0, 0), (1_000, 0)])
        var progress = ItineraryProgress(track: line, total: Distance(meters: 1_000))

        progress.update(with: fix(east: 600, north: 10))

        #expect(progress.status == .onTrack)
        #expect(abs(remaining(progress)! - 400) < 2)
    }

    @Test func aFigureEightKeepsItsPlaceAtTheCrossing() {
        // Two 200 m squares sharing the corner (200, 0): west square, then east square.
        let eight = SyntheticTrack.through([(200, 0), (0, 0), (0, 200), (200, 200), (200, 0), (400, 0), (400, -200), (200, -200), (200, 0)])
        let length = 1_600.0
        var progress = ItineraryProgress(track: eight, total: Distance(meters: length))
        var lastRemaining = length

        // Walk the whole track every 10 m: the distance left only ever goes down.
        let corners: [(Double, Double)] = [(200, 0), (0, 0), (0, 200), (200, 200), (200, 0), (400, 0), (400, -200), (200, -200), (200, 0)]
        for (from, to) in zip(corners, corners.dropFirst()) {
            for step in stride(from: 0.0, to: 200, by: 10) {
                let t = step / 200
                progress.update(with: fix(east: from.0 + (to.0 - from.0) * t, north: from.1 + (to.1 - from.1) * t))
                let left = remaining(progress)!
                #expect(left <= lastRemaining + 0.01)
                lastRemaining = left
            }
            if to == (200, 0), from == (200, 200) {
                // Back at the crossing halfway: the second square is still ahead.
                #expect(abs(lastRemaining - 800) < 12)
            }
        }
        progress.update(with: fix(east: 200, north: -2))

        #expect(progress.status == .finished)
    }

    @Test func aShortcutFreezesOffTheTrackThenLowersTheDistanceLeft() {
        var progress = ItineraryProgress(track: loop, total: Distance(meters: 1_600))
        for east in stride(from: 0.0, through: 400, by: 20) {
            progress.update(with: fix(east: east, north: 0))
        }
        #expect(abs(remaining(progress)! - 1_200) < 2)

        // Across the square, from the south-east corner to the north-west one.
        progress.update(with: fix(east: 300, north: 100))
        progress.update(with: fix(east: 200, north: 200))
        #expect(progress.status == .offTrack)
        #expect(abs(remaining(progress)! - 1_200) < 2)
        progress.update(with: fix(east: 100, north: 300))
        progress.update(with: fix(east: 10, north: 390))

        #expect(progress.status == .onTrack)
        #expect(abs(remaining(progress)! - 400) < 15)
    }

    @Test func aUTurnOnTheTrackFreezesTheDistanceLeft() {
        let line = SyntheticTrack.through([(0, 0), (1_000, 0)])
        var progress = ItineraryProgress(track: line, total: Distance(meters: 1_000))
        for east in stride(from: 0.0, through: 500, by: 10) {
            progress.update(with: fix(east: east, north: 0))
        }

        for east in stride(from: 490.0, through: 300, by: -10) {
            progress.update(with: fix(east: east, north: 0))
            #expect(abs(remaining(progress)! - 500) < 0.5)
        }
    }

    @Test func anInaccurateFixIsIgnored() {
        var progress = ItineraryProgress(track: loop, total: Distance(meters: 1_600))

        progress.update(with: fix(east: 200, north: 0, accuracy: 80))

        #expect(progress.status == .notSnapped)
    }

    @Test func aStartedLoopDoesNotGoBackToItsStartOnceReopened() {
        var before = ItineraryProgress(track: loop, total: Distance(meters: 1_600))
        before.update(with: fix(east: 0, north: 0))
        before.update(with: fix(east: 400, north: 0))
        before.update(with: fix(east: 400, north: 400))
        before.update(with: fix(east: 0, north: 400))
        before.update(with: fix(east: 0, north: 100))
        #expect(abs(remaining(before)! - 100) < 2)

        // Reopened from what was saved, with a first position 40 m from the start of the loop.
        var reopened = ItineraryProgress(track: loop, total: Distance(meters: 1_600), saved: before.saved)
        reopened.update(with: fix(east: 0, north: 40))

        #expect(reopened.status == .onTrack)
        #expect(abs(remaining(reopened)! - 40) < 2)
    }
}
