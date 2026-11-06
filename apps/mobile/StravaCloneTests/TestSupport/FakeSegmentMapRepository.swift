import Foundation
@testable import StravaClone

/// Hand-written `SegmentMapRepository`: answers `segments` (filtered like the API by sport and
/// `isFavorite`), or `error`; records each search.
final class FakeSegmentMapRepository: SegmentMapRepository, @unchecked Sendable {
    struct Search: Equatable {
        let area: MapArea
        let filter: SegmentMapFilter
    }

    private let state = Locked<(segments: [MapSegment], error: SegmentError?, searches: [Search])>(([], nil, []))

    var segments: [MapSegment] {
        get { state.value.segments }
        set { state.value.segments = newValue }
    }

    var error: SegmentError? {
        get { state.value.error }
        set { state.value.error = newValue }
    }

    var searches: [Search] { state.value.searches }

    func segments(in area: MapArea, filter: SegmentMapFilter) async throws(SegmentError) -> [MapSegment] {
        state.value.searches.append(Search(area: area, filter: filter))
        if let error = state.value.error { throw error }
        return state.value.segments.filter { segment in
            (filter.sport == nil || segment.sport == filter.sport) && (!filter.favoritesOnly || segment.isFavorite)
        }
    }
}

extension MapSegment {
    static func fixture(
        _ id: String,
        sport: SegmentSport = .ride,
        name: String = "Montée du Semnoz",
        isFavorite: Bool = false,
        start: Coordinate = Coordinate(latitude: 45.90, longitude: 6.13),
        myBestTime: Duration? = nil,
        leaderTime: Duration? = .seconds(754)
    ) -> MapSegment {
        MapSegment(
            id: id,
            sport: sport,
            name: name,
            isVerified: false,
            isFavorite: isFavorite,
            distance: Distance(meters: 6_800),
            averageGradePct: 7.4,
            climbCategory: .cat2,
            athleteCount: 12,
            myBestTime: myBestTime,
            leaderTime: leaderTime,
            path: [start, Coordinate(latitude: start.latitude + 0.01, longitude: start.longitude)]
        )
    }
}

extension MapArea {
    /// About a screen around Annecy at `zoom`.
    static func annecy(zoom: Double = 12.5, shiftedEastBy shift: Double = 0) -> MapArea {
        MapArea(
            southWest: Coordinate(latitude: 45.88, longitude: 6.10 + shift),
            northEast: Coordinate(latitude: 45.92, longitude: 6.16 + shift),
            zoom: zoom
        )
    }
}
