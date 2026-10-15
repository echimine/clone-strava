import Foundation

/// Read side of the Itinerary cache (ADR-031 §15), for features other than Itineraries,
/// which alone writes it. Works offline: it only reads what the phone already holds.
protocol ItineraryCacheReader: Sendable {
    /// Every cached Itinerary, most recently updated first; those pending deletion left out,
    /// a pending rename shown.
    func cachedItineraries() async throws -> [CachedItineraryListing]
    /// The cached track of one Itinerary; nil when its track is not on the phone, or when it
    /// is no longer listed (deleted, or pending deletion).
    func track(of id: ItineraryID) async throws -> CachedItineraryTrack?
}

/// One cached Itinerary, as a picker lists it.
struct CachedItineraryListing: Identifiable, Equatable, Sendable {
    let id: ItineraryID
    let name: String
    let sport: SportType
    let distance: Distance
    /// Its track is on the phone: it can be followed offline.
    let hasTrack: Bool
}

/// The path of a cached Itinerary, to follow it.
struct CachedItineraryTrack: Equatable, Sendable {
    let id: ItineraryID
    /// From start to finish, resampled every ~20 m by the API.
    let points: [Coordinate]
    /// Total distance as the API measured it.
    let distance: Distance
}
