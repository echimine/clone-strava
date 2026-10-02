import Foundation

/// Route in Google's encoded polyline format (ADR-029): sent as is to the Mapbox Static
/// Images API, decoded only to place the start and end pins.
struct EncodedPolyline: Hashable, Sendable {
    let value: String
    var precision: Int = 5

    /// Decoded coordinates; an empty array for a malformed string.
    func decode() -> [Coordinate] {
        let factor = pow(10, Double(precision))
        let bytes = Array(value.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var coordinates: [Coordinate] = []

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                guard byte >= 0 else { return nil }
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : result >> 1
                }
            }
            return nil
        }

        while index < bytes.count {
            guard let deltaLat = nextValue(), let deltaLon = nextValue() else { return [] }
            latitude += deltaLat
            longitude += deltaLon
            coordinates.append(Coordinate(latitude: Double(latitude) / factor, longitude: Double(longitude) / factor))
        }
        return coordinates
    }
}
