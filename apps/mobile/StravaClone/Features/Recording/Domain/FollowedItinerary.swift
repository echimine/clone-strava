import Foundation

/// The Itinerary followed during a Recording (ADR-031 §2, §6, §10): the copy loaded from the
/// cache at Start, kept until the end even if the Itinerary is deleted elsewhere, and its
/// progress. It can be removed, never replaced.
struct FollowedItinerary: Equatable, Sendable {
    let id: ItineraryID
    let name: String
    /// The cached track, start to finish.
    let track: [Coordinate]
    var progress: ItineraryProgress

    /// - Parameter total: the distance the API measured.
    init(id: ItineraryID, name: String, track: [Coordinate], total: Distance, saved: ItineraryProgress.Saved? = nil) {
        self.id = id
        self.name = name
        self.track = track
        progress = ItineraryProgress(track: track, total: total, saved: saved)
    }

    init(_ track: CachedItineraryTrack, name: String) {
        self.init(id: track.id, name: name, track: track.points, total: track.distance)
    }
}
