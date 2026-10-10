import Foundation

/// What `POST /v1/itineraries` needs (ADR-030 §6): the app-generated id, so a replay after
/// a lost answer does not create a duplicate.
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
/// #35 adds the detail read, #38 rename and delete.
protocol ItineraryRepository: Sendable {
    /// Creates the Itinerary, or returns it unchanged when the same athlete replays the id.
    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail
    /// One page of the athlete's Itineraries, most recently updated first.
    func page(cursor: String?) async throws(ItineraryError) -> ItineraryPage
}

/// Local copy of the athlete's Itineraries (ADR-008 §1, ADR-030 §8): screens read it, the
/// network writes to it. Implemented over GRDB.
protocol ItineraryCache: Sendable {
    /// The first `limit` Itineraries, most recently updated first, then again after each change.
    func observeSummaries(limit: Int) -> AsyncStream<[ItinerarySummary]>
    func summaries(limit: Int) async throws -> [ItinerarySummary]
    func detail(id: ItineraryID) async throws -> ItineraryDetail?
    /// Writes a detail just received (after a save), with the row shown in the list.
    func save(_ detail: ItineraryDetail, mapPolyline: EncodedPolyline) async throws
    /// Full resync: inserts or updates every row, deletes the ones no longer returned with
    /// their detail. A detail older than its row is kept until it is fetched again.
    func replaceSummaries(with summaries: [ItinerarySummary]) async throws
    /// Sign-out: forgets every Itinerary.
    func clear() async throws
}
