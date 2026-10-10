import Foundation

/// What `POST /v1/itineraries` needs (ADR-030 §6): the app-generated id, so a replay after
/// a lost answer does not create a duplicate. `PUT /v1/itineraries/:id` sends the same
/// content for an existing id.
struct ItineraryCreation: Equatable, Sendable {
    /// A Leg as sent to the API: a `follow` Leg carries the router's geometry as is.
    enum Leg: Equatable, Sendable {
        case follow(EncodedPolyline)
        case straight
    }

    let id: ItineraryID
    let name: String
    let sport: ItinerarySport
    let waypoints: [Coordinate]
    let legs: [Leg]
}

/// Itinerary API port (ADR-007): implemented over `/v1/itineraries`, faked in tests.
protocol ItineraryRepository: Sendable {
    /// Creates the Itinerary, or returns it unchanged when the same athlete replays the id.
    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail
    /// One page of the athlete's Itineraries, most recently updated first.
    func page(cursor: String?) async throws(ItineraryError) -> ItineraryPage
    /// The detail kept for offline viewing; `notFound` once deleted (or never the athlete's).
    func detail(id: ItineraryID) async throws(ItineraryError) -> ItineraryDetail
    /// `PATCH`: the renamed Itinerary. Any client error but `404` is `invalid`.
    func rename(id: ItineraryID, to name: String) async throws(ItineraryError) -> ItineraryDetail
    /// `DELETE`, answered `204`. Any client error but `404` is `invalid`.
    func delete(id: ItineraryID) async throws(ItineraryError)
    /// Waypoints and Legs as stored, for "Modifier"; `notFound` once deleted.
    func savedItinerary(id: ItineraryID) async throws(ItineraryError) -> SavedItinerary
    /// Replaces the whole Itinerary under its id (name, sport, Waypoints, Legs), recomputed.
    func update(_ edit: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail
}

/// What the cache holds about one Itinerary, as its detail screen observes it.
struct CachedItinerary: Equatable, Sendable {
    /// The list row, kept current by every resync.
    let summary: ItinerarySummary
    /// Track and altitudes; nil until fetched once.
    let detail: ItineraryDetail?

    /// The detail is missing, or the Itinerary changed since it was fetched (ADR-030 §8).
    var needsDetail: Bool {
        detail?.updatedAt != summary.updatedAt
    }
}

/// Local copy of the athlete's Itineraries (ADR-008 §1, ADR-030 §8): screens read it, the
/// network writes to it. Implemented over GRDB.
protocol ItineraryCache: Sendable {
    /// The first `limit` Itineraries, most recently updated first, then again after each change.
    func observeSummaries(limit: Int) -> AsyncStream<[ItinerarySummary]>
    /// One Itinerary, then again after each change; nil while it is not (or no longer) cached:
    /// deleted here (or pending deletion), on another device, or gone from the last resync.
    /// Lists and details show the name of a pending rename (ADR-030 §8).
    func observeItinerary(id: ItineraryID) -> AsyncStream<CachedItinerary?>
    func summaries(limit: Int) async throws -> [ItinerarySummary]
    func detail(id: ItineraryID) async throws -> ItineraryDetail?
    /// When the cached row last changed on the server; nil when not cached. An Itinerary
    /// pending deletion still answers: the comparison with a realtime save needs it (#39).
    func updatedAt(id: ItineraryID) async throws -> Date?
    /// Writes a detail just received (after a save), with the row shown in the list.
    func save(_ detail: ItineraryDetail, mapPolyline: EncodedPolyline) async throws
    /// The Itineraries whose detail is missing or older than their row: to prefetch.
    func idsWithStaleDetail() async throws -> [ItineraryID]
    /// Writes a detail fetched from the API and refreshes its row, list thumbnail kept.
    /// Ignored when the Itinerary is no longer listed: a deleted Itinerary stays deleted.
    func store(_ detail: ItineraryDetail) async throws
    /// Forgets one Itinerary, its detail and its pending changes (`404`, deleted elsewhere:
    /// `itinerary.deleted`, #39).
    func delete(id: ItineraryID) async throws
    /// Full resync: inserts or updates every row, deletes the ones no longer returned with
    /// their detail, unless a pending change targets them. A detail older than its row is kept until it is fetched again.
    func replaceSummaries(with summaries: [ItinerarySummary]) async throws
    /// Sign-out: forgets every Itinerary.
    func clear() async throws
}
