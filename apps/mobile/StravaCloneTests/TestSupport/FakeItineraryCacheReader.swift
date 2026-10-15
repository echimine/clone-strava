import Foundation
@testable import StravaClone

/// In-memory `ItineraryCacheReader`: what the phone holds of the athlete's Itineraries.
final class FakeItineraryCacheReader: ItineraryCacheReader, @unchecked Sendable {
    private let lock = NSLock()
    private var listings: [CachedItineraryListing]
    private var tracks: [ItineraryID: CachedItineraryTrack]

    init(listings: [CachedItineraryListing] = [], tracks: [CachedItineraryTrack] = []) {
        self.listings = listings
        self.tracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    }

    /// The Itinerary was deleted elsewhere: neither listed nor loadable any more.
    func delete(_ id: ItineraryID) {
        lock.withLock {
            listings.removeAll { $0.id == id }
            tracks[id] = nil
        }
    }

    func cachedItineraries() async throws -> [CachedItineraryListing] {
        lock.withLock { listings }
    }

    func track(of id: ItineraryID) async throws -> CachedItineraryTrack? {
        lock.withLock { tracks[id] }
    }
}
