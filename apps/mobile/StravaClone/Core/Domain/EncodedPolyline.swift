import Foundation

/// Route in Google's encoded polyline format (ADR-029): sent as is to the Mapbox Static
/// Images API, decoded only to place the start and end pins. Itinerary Legs travel as
/// polyline6 (ADR-030 §6).
struct EncodedPolyline: Hashable, Sendable {
    let value: String
    var precision: Int = 5

    init(value: String, precision: Int = 5) {
        self.value = value
        self.precision = precision
    }

    /// Encodes coordinates, rounded to `precision` decimals.
    init(encoding coordinates: [Coordinate], precision: Int = 5) {
        let factor = pow(10, Double(precision))
        var output: [UInt8] = []
        var previous = (latitude: 0, longitude: 0)

        func append(_ delta: Int) {
            var value = delta < 0 ? ~(delta << 1) : delta << 1
            while value >= 0x20 {
                output.append(UInt8((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            }
            output.append(UInt8(value + 63))
        }

        for coordinate in coordinates {
            let latitude = Int((coordinate.latitude * factor).rounded())
            let longitude = Int((coordinate.longitude * factor).rounded())
            append(latitude - previous.latitude)
            append(longitude - previous.longitude)
            previous = (latitude, longitude)
        }
        self.init(value: String(decoding: output, as: UTF8.self), precision: precision)
    }

    /// A list thumbnail of a path (ADR-030 §6, ADR-031 §14): polyline5 of at most
    /// `maxCharacters`, thinned by keeping one point in 2, 4, 8… and always the last one, like
    /// the API's `map_polyline`.
    static func thumbnail(of points: [Coordinate], maxCharacters: Int = 2_000) -> EncodedPolyline {
        var step = 1
        while true {
            var kept = Swift.stride(from: 0, to: points.count, by: step).map { points[$0] }
            if let last = points.last, (points.count - 1) % step != 0 {
                kept.append(last)
            }
            let encoded = EncodedPolyline(encoding: kept)
            if encoded.value.count <= maxCharacters || kept.count <= 2 {
                return encoded
            }
            step *= 2
        }
    }

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
