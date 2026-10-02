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
}
