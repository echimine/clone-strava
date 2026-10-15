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

    /// A local Activity's card (ADR-031 §14): polyline5 of at most 2,000 characters, from start
    /// to finish, whatever the number of points.
    @Test func aLongTraceBecomesAThumbnailOfAtMost2000CharactersKeepingBothEnds() {
        let points = (0 ..< 5_001).map { index in
            Coordinate(latitude: 45.0 + Double(index) * 0.000_13, longitude: 6.0 + sin(Double(index) / 40) * 0.01)
        }

        let thumbnail = EncodedPolyline.thumbnail(of: points)
        let decoded = thumbnail.decode()

        #expect(thumbnail.precision == 5)
        #expect(thumbnail.value.count <= 2_000)
        #expect(decoded.count > 100)
        #expect(decoded.first == EncodedPolyline(encoding: [points[0]]).decode().first)
        #expect(decoded.last == EncodedPolyline(encoding: [points[5_000]]).decode().first)
    }

    @Test func aShortTraceIsKeptWhole() {
        let points = [Coordinate(latitude: 45.1, longitude: 6.1), Coordinate(latitude: 45.2, longitude: 6.2)]
        #expect(EncodedPolyline.thumbnail(of: points) == EncodedPolyline(encoding: points))
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
