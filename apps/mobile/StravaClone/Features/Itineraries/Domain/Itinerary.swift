import Foundation

/// One row of "Mes Itinéraires" (ADR-030 §6 `GET /v1/itineraries`).
struct ItinerarySummary: Identifiable, Equatable, Sendable {
    let id: ItineraryID
    var name: String
    var sport: SportType
    var distance: Distance
    var elevationGain: Double
    /// Simplified path (polyline5, at most 2,000 characters): thumbnail of the card.
    var mapPolyline: EncodedPolyline
    var updatedAt: Date
}

/// Path of a saved Itinerary, resampled every ~20 m by the API, with one altitude per point.
struct ItineraryTrack: Equatable, Sendable {
    /// polyline6.
    let polyline: EncodedPolyline
    let altitudes: [Double]
}

extension ItineraryTrack {
    /// The track as a list thumbnail: polyline5 of at most `maxCharacters`, thinned by keeping
    /// one point in 2, 4, 8… and always the last one, like the API's `map_polyline`.
    func mapPolyline(maxCharacters: Int = 2_000) -> EncodedPolyline {
        EncodedPolyline.thumbnail(of: polyline.decode(), maxCharacters: maxCharacters)
    }
}

/// What the app keeps of an Itinerary for offline viewing (ADR-030 §8): everything but its
/// Waypoints and Legs, which "Modifier" loads online.
struct ItineraryDetail: Identifiable, Equatable, Sendable {
    let id: ItineraryID
    var name: String
    var sport: SportType
    var distance: Distance
    var elevationGain: Double
    var elevationSource: ElevationSource
    var track: ItineraryTrack
    var createdAt: Date
    var updatedAt: Date
}

/// One page of `GET /v1/itineraries`: `nextCursor` is nil on the last page.
struct ItineraryPage: Equatable, Sendable {
    let items: [ItinerarySummary]
    let nextCursor: String?
}

/// Failures of the Itinerary API, as the app needs them.
enum ItineraryError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// Unknown Itinerary, or one owned by another athlete (`404`).
    case notFound
    /// The id belongs to another athlete (`409`).
    case conflict
    /// An elevation provider failed during the save (`503`): worth retrying.
    case unavailable
    /// Rejected by the API (`422`), with its machine-readable code.
    case invalid(code: String?)
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    /// Timeout, connection lost, unreadable answer.
    case network

    /// A replay with the same id may succeed: the request may even have been written
    /// before the connection dropped.
    var isRetryable: Bool {
        switch self {
        case .offline, .unavailable, .server, .network: true
        case .unauthorized, .notFound, .conflict, .invalid: false
        }
    }
}
