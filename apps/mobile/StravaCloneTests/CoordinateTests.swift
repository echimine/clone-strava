import Testing
@testable import StravaClone

struct CoordinateTests {
    @Test func distanceBetweenIdenticalPointsIsZero() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        #expect(paris.distance(to: paris) == .zero)
    }

    @Test func distanceParisToLyonIsAbout392Kilometers() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        let lyon = Coordinate(latitude: 45.7640, longitude: 4.8357)
        #expect(abs(paris.distance(to: lyon).kilometers - 391.5) < 1)
    }

    @Test(arguments: [
        (Coordinate(latitude: 91, longitude: 0), false),
        (Coordinate(latitude: 0, longitude: -181), false),
        (Coordinate(latitude: 45, longitude: 5), true),
    ])
    func validity(coordinate: Coordinate, expected: Bool) {
        #expect(coordinate.isValid == expected)
    }
}
