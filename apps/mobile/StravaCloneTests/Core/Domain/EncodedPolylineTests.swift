import Foundation
import Testing
@testable import StravaClone

struct EncodedPolylineTests {
    @Test func decodesGooglesReferenceVector() {
        let coordinates = EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@").decode()
        #expect(coordinates == [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453),
        ])
    }

    @Test func malformedInputDecodesToNothing() {
        #expect(EncodedPolyline(value: "_p~iF").decode().isEmpty)
        #expect(EncodedPolyline(value: "").decode().isEmpty)
    }

    @Test func encodesGooglesReferenceVector() {
        let polyline = EncodedPolyline(encoding: [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453),
        ])
        #expect(polyline == EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"))
    }

    /// Itinerary Legs are sent as polyline6 (ADR-030 §6): a Mapbox geometry survives the round trip.
    @Test func roundTripsAtPrecisionSix() {
        let coordinates = [
            Coordinate(latitude: 45.899_123, longitude: 6.129_456),
            Coordinate(latitude: 45.900_001, longitude: 6.120_999),
        ]
        let polyline = EncodedPolyline(encoding: coordinates, precision: 6)
        #expect(polyline.precision == 6)
        #expect(polyline.decode() == coordinates)
    }
}
