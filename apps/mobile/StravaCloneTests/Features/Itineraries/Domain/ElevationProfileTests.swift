import Foundation
import Testing
@testable import StravaClone

/// The elevation profile of the detail (ADR-030 §3): altitude against the distance covered,
/// from the stored track, without any network call.
struct ElevationProfileTests {
    private func track(latitudes: [Double], altitudes: [Double]) -> ItineraryTrack {
        ItineraryTrack(
            polyline: EncodedPolyline(
                encoding: latitudes.map { Coordinate(latitude: $0, longitude: 6.12) },
                precision: 6
            ),
            altitudes: altitudes
        )
    }

    @Test func eachAltitudeIsPlacedAtTheDistanceCoveredAlongTheTrack() {
        let profile = track(latitudes: [45.9, 45.91, 45.92], altitudes: [446.5, 480, 534]).elevationProfile()

        // 0.01° of latitude is 1,111.95 m on the mean Earth radius.
        #expect(profile.points.map(\.altitude) == [446.5, 480, 534])
        let distances = profile.points.map(\.distance.meters)
        #expect(distances[0] == 0)
        #expect(abs(distances[1] - 1_111.95) < 0.5)
        #expect(abs(distances[2] - 2_223.9) < 1)
        #expect(profile.altitudeRange == 446.5...534)
    }

    @Test func aLongTrackIsThinnedButKeepsItsEndsAndItsHighAndLowPoints() {
        let latitudes = (0..<1_000).map { 45.0 + Double($0) * 0.0002 }
        var altitudes = (0..<1_000).map { 500 + Double($0 % 10) }
        altitudes[333] = 1_200
        altitudes[667] = 100

        let profile = track(latitudes: latitudes, altitudes: altitudes).elevationProfile(maxPoints: 100)

        #expect(profile.points.count <= 100)
        #expect(profile.points.first?.altitude == 500)
        #expect(profile.points.first?.distance.meters == 0)
        #expect(abs((profile.points.last?.distance.meters ?? 0) - 22_217) < 5)
        #expect(profile.points.contains { $0.altitude == 1_200 })
        #expect(profile.points.contains { $0.altitude == 100 })
        #expect(profile.altitudeRange == 100...1_200)
    }

    @Test func pointsWithoutAnAltitudeAreLeftOut() {
        let profile = track(latitudes: [45.9, 45.91, 45.92], altitudes: [446.5, 480]).elevationProfile()

        #expect(profile.points.map(\.altitude) == [446.5, 480])
    }

    @Test func aTrackWithoutAltitudesHasNoProfile() {
        let profile = track(latitudes: [45.9, 45.91], altitudes: []).elevationProfile()

        #expect(profile.points.isEmpty)
        #expect(profile.altitudeRange == nil)
    }
}
