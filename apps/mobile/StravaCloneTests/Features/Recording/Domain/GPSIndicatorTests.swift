import Foundation
import Testing
@testable import StravaClone

struct GPSIndicatorTests {
    private func position(accuracy: Double) -> LocationSample {
        .fixture(latitude: 45.764, longitude: 4.8357, accuracy: accuracy)
    }

    @Test func searchesUntilAFirstPosition() {
        #expect(GPSIndicator(position: nil, isAccuracyReduced: false) == .searching)
    }

    @Test func isReadyWithinFiftyMeters() {
        #expect(GPSIndicator(position: position(accuracy: 50), isAccuracyReduced: false) == .ready)
        #expect(GPSIndicator(position: position(accuracy: 65), isAccuracyReduced: false) == .approximate)
    }

    @Test func isApproximateWithoutPreciseLocation() {
        #expect(GPSIndicator(position: position(accuracy: 5), isAccuracyReduced: true) == .approximate)
    }
}
