import Foundation
import Observation

/// State of Profil > Mes Itinéraires (ADR-030 §8): the cache is the only source of the
/// cards (ADR-008 §1), shown page by page; the network only writes to the cache through a
/// full resync. Offline, the cards stay and a message says they come from the device.
@Observable
@MainActor
final class ItineraryListStore {
    private(set) var itineraries: [ItinerarySummary] = []
    /// The cache answered at least once: an empty list is really empty.
    private(set) var hasLoaded = false
    /// Cards read from the cache; grows by one page when the last card appears.
    private(set) var limit: Int
    /// Why the last refresh failed, shown above the cards.
    private(set) var syncMessage: String?

    @ObservationIgnored private let cache: any ItineraryCache
    @ObservationIgnored private let synchronizer: ItinerarySynchronizer
    @ObservationIgnored private let pageSize: Int

    init(cache: any ItineraryCache, synchronizer: ItinerarySynchronizer, pageSize: Int = 20) {
        self.cache = cache
        self.synchronizer = synchronizer
        self.pageSize = pageSize
        limit = pageSize
    }

    var isEmpty: Bool { hasLoaded && itineraries.isEmpty }

    /// Runs for the lifetime of the view, restarted when `limit` changes (`.task(id:)`).
    func observe() async {
        for await summaries in cache.observeSummaries(limit: limit) {
            itineraries = summaries
            hasLoaded = true
        }
    }

    /// On opening and pull-to-refresh: full resync.
    func refresh() async {
        do {
            try await synchronizer.refresh()
            syncMessage = nil
        } catch {
            syncMessage = ItineraryMessages.syncFailed(error)
        }
    }

    /// Called when a card appears: the last one asks the cache for one more page.
    func loadMoreIfNeeded(current: ItinerarySummary) {
        guard current.id == itineraries.last?.id, itineraries.count >= limit else { return }
        limit += pageSize
    }
}

/// "Créer" from the Map tab or Mes Itinéraires: the editor needs the network (ADR-030 §8),
/// so offline the button stays active and shows "Connexion requise".
@Observable
@MainActor
final class ItineraryCreationFlow {
    var isPresented = false
    var toast: String?

    @ObservationIgnored private let isOnline: @MainActor () -> Bool

    init(isOnline: @escaping @MainActor () -> Bool) {
        self.isOnline = isOnline
    }

    func start() {
        if isOnline() {
            isPresented = true
        } else {
            toast = ItineraryMessages.connectionRequired
        }
    }
}
