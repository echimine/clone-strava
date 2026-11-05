import Foundation

/// What a map shows once its camera settles (ADR-039 §15): the visible bounds and the zoom.
/// Independent of Mapbox (ADR-007 rule 6).
struct MapArea: Equatable, Sendable {
    let southWest: Coordinate
    let northEast: Coordinate
    let zoom: Double

    var center: Coordinate {
        Coordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }

    private var latitudeSpan: Double { northEast.latitude - southWest.latitude }
    private var longitudeSpan: Double { northEast.longitude - southWest.longitude }

    /// Moved or zoomed enough that a search made on `other` no longer matches what is shown:
    /// the centre left the middle half of `other`, or the zoom changed by more than 0.8.
    func isAway(from other: MapArea) -> Bool {
        abs(zoom - other.zoom) > 0.8
            || abs(center.latitude - other.center.latitude) > other.latitudeSpan / 4
            || abs(center.longitude - other.center.longitude) > other.longitudeSpan / 4
    }
}
