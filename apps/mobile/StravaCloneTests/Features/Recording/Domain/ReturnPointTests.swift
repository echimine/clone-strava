import Foundation
import Testing
@testable import StravaClone

/// Where a Return path leads (ADR-031 §7): the track point ahead of the progress closest to the
/// athlete as the crow flies, the start of the Itinerary before the first snap.
struct ReturnPointTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    /// A 400 m square, start = finish at the south-west corner, anticlockwise: east, north, west, south.
    private let loop = SyntheticTrack.through([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)])
    /// 1 km east, then back to the start on the same road.
    private let outAndBack = SyntheticTrack.through([(0, 0), (1_000, 0), (0, 0)])

    private func progress(
        on track: [Coordinate],
        total: Double,
        after positions: [(east: Double, north: Double)]
    ) -> ItineraryProgress {
        var progress = ItineraryProgress(track: track, total: Distance(meters: total))
        for position in positions {
            progress.update(with: LocationSample(
                coordinate: SyntheticTrack.point(east: position.east, north: position.north),
                altitude: nil,
                horizontalAccuracy: 5,
                timestamp: start
            ))
        }
        return progress
    }

    private func expectNear(_ coordinate: Coordinate?, east: Double, north: Double) {
        guard let coordinate else {
            Issue.record("no return point")
            return
        }
        #expect(coordinate.distance(to: SyntheticTrack.point(east: east, north: north)).meters < 2)
    }

    @Test func onALoopTheClosestPointAheadIsAShortcut() throws {
        let progress = progress(on: loop, total: 1_600, after: [(0, 0), (100, 0)])

        let point = try #require(progress.returnPoint(for: SyntheticTrack.point(east: 100, north: 330)))

        expectNear(point.coordinate, east: 100, north: 400)
        #expect(abs(progress.remaining(from: point).meters - 500) < 2)
    }

    @Test func aPointBehindTheProgressIsNeverChosen() throws {
        let progress = progress(on: loop, total: 1_600, after: [(0, 0), (400, 0), (400, 200)])

        // Closest to the bottom edge, already done: the way back to the track is the finish.
        let point = try #require(progress.returnPoint(for: SyntheticTrack.point(east: 100, north: -60)))

        expectNear(point.coordinate, east: 0, north: 0)
        #expect(progress.remaining(from: point).meters < 2)
    }

    @Test func onTheWayOutOfAnOutAndBackItLeadsToTheWayOut() throws {
        let progress = progress(on: outAndBack, total: 2_000, after: [(0, 0), (300, 0)])

        let point = try #require(progress.returnPoint(for: SyntheticTrack.point(east: 500, north: 100)))

        expectNear(point.coordinate, east: 500, north: 0)
        #expect(abs(progress.remaining(from: point).meters - 1_500) < 2)
    }

    @Test func onTheWayBackOfAnOutAndBackItLeadsToTheWayBack() throws {
        var positions: [(east: Double, north: Double)] = stride(from: 0.0, through: 1_000, by: 20).map { ($0, 2) }
        positions += stride(from: 1_000.0, through: 800, by: -20).map { ($0, -2) }
        let progress = progress(on: outAndBack, total: 2_000, after: positions)

        let point = try #require(progress.returnPoint(for: SyntheticTrack.point(east: 500, north: 100)))

        expectNear(point.coordinate, east: 500, north: 0)
        #expect(abs(progress.remaining(from: point).meters - 500) < 2)
    }

    @Test func beforeTheFirstSnapItLeadsToTheStart() throws {
        let progress = progress(on: loop, total: 1_600, after: [(200, -300)])

        let point = try #require(progress.returnPoint(for: SyntheticTrack.point(east: 200, north: -300)))

        expectNear(point.coordinate, east: 0, north: 0)
        #expect(progress.remaining(from: point) == Distance(meters: 1_600))
    }
}
