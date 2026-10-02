import Foundation
import Testing
@testable import StravaClone

struct StaticMapURLTests {
    private let route = EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")

    @Test func buildsAnOutdoorsURLWithPathAndPins() throws {
        let url = try #require(StaticMapURL.make(route: route, size: CGSize(width: 360, height: 202.5), accessToken: "pk.test"))
        let string = url.absoluteString

        #expect(string.hasPrefix("https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/path-4+FC5200-1("))
        // `|`, `` ` `` and `@` are percent-encoded inside the path overlay.
        #expect(string.contains("_p~iF~ps%7CU_ulLnnqC_mqNvxq%60%40"))
        #expect(string.contains("pin-s+2ECC71(-120.20000,38.50000)"))
        #expect(string.contains("pin-s+E74C3C(-126.45300,43.25200)"))
        #expect(string.contains("/auto/360x203@2x?"))
        #expect(string.hasSuffix("access_token=pk.test"))
    }

    @Test func returnsNilWhenItCannotDraw() {
        #expect(StaticMapURL.make(route: route, size: CGSize(width: 300, height: 200), accessToken: "") == nil)
        #expect(StaticMapURL.make(route: EncodedPolyline(value: "_p~iF~ps|U"), size: CGSize(width: 300, height: 200), accessToken: "pk") == nil)
        #expect(StaticMapURL.make(route: route, size: .zero, accessToken: "pk") == nil)
    }

    @Test func returnsNilAboveMapboxLengthLimit() {
        let long = EncodedPolyline(value: String(repeating: "_p~iF~ps|U", count: 900))
        #expect(StaticMapURL.make(route: long, size: CGSize(width: 300, height: 200), accessToken: "pk") == nil)
    }
}
