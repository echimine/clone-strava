import Foundation

/// WGS 84 position, independent of Core Location and Mapbox (ADR-002, ADR-007 rule 6).
struct Coordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Great-circle distance (haversine formula).
    func distance(to other: Coordinate) -> Distance {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return Distance(meters: 2 * earthRadius * asin(min(1, sqrt(a))))
    }
}
