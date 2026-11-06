import Foundation

extension ItineraryTrack {
    /// The profile drawn in the detail (ADR-030 §3), from the cached track.
    func elevationProfile(maxPoints: Int = 400) -> ElevationProfile {
        ElevationProfile(coordinates: polyline.decode(), altitudes: altitudes, maxPoints: maxPoints)
    }
}
