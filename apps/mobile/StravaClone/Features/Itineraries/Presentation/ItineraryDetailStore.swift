import Foundation
import Observation

/// State of an Itinerary's detail (ADR-030 §8), wherever it is shown: page pushed from Mes
/// Itinéraires, Map tab sheet (#36). It only reads the cache (ADR-008 §1), so it shows
/// offline whatever was prefetched; a detail not prefetched yet, or older than its row, is
/// fetched once on opening. The cache is observed live: a rename (#38) or an edit (#37)
/// shows at once, and the screen closes (`isGone`) when the Itinerary leaves the cache,
/// whether deleted here (#38), on another device (#39) or answered `404`.
@Observable
@MainActor
final class ItineraryDetailStore {
    let id: ItineraryID
    /// The list row: name, sport and figures, shown even before the detail is there.
    private(set) var summary: ItinerarySummary?
    /// Track, altitudes and their source; nil until fetched once.
    private(set) var detail: ItineraryDetail?
    private(set) var profile: ElevationProfile?
    /// Why the track is missing (never fetched, and the fetch failed).
    private(set) var trackMessage: String?
    /// The Itinerary is no longer cached: the screen closes.
    private(set) var isGone = false

    @ObservationIgnored private let cache: any ItineraryCache
    @ObservationIgnored private let synchronizer: ItinerarySynchronizer
    @ObservationIgnored private var hasRequestedDetail = false
    @ObservationIgnored private let source: AnalyticsEvent.ListSource
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    @ObservationIgnored private var hasBeenViewed = false

    /// - Parameters:
    ///   - source: where the detail is shown, for its journey event (issue #20).
    ///   - isOnline: whether a network route exists, sent with that event.
    init(
        id: ItineraryID,
        cache: any ItineraryCache,
        synchronizer: ItinerarySynchronizer,
        source: AnalyticsEvent.ListSource = .profile,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        isOnline: @escaping @MainActor () -> Bool = { true }
    ) {
        self.id = id
        self.cache = cache
        self.synchronizer = synchronizer
        self.source = source
        self.analytics = analytics
        self.isOnline = isOnline
    }

    /// Runs for the lifetime of the screen (`.task`). The fetch runs beside the observation,
    /// so a slow answer never holds back what the cache shows. The opening is sent once,
    /// not each time the screen shows again (back from the editor).
    func observe() async {
        if !hasBeenViewed {
            hasBeenViewed = true
            analytics.capture(.itineraryViewed(itineraryId: id.description, source: source, offline: !isOnline()))
        }
        await withTaskGroup(of: Void.self) { group in
            for await cached in cache.observeItinerary(id: id) {
                guard let cached else {
                    isGone = true
                    group.cancelAll()
                    return
                }
                show(cached)
                if cached.needsDetail, !hasRequestedDetail {
                    hasRequestedDetail = true
                    group.addTask { await self.fetchDetail() }
                }
            }
        }
    }

    /// Renommer (ADR-030 §8): the new name shows at once, offline too, and is sent later.
    /// `false` when the name does not have 1 to 100 characters.
    func rename(to name: String) async -> Bool {
        do {
            try await synchronizer.rename(id: id, to: name)
            return true
        } catch {
            return false
        }
    }

    /// Supprimer, once confirmed: the Itinerary disappears at once and the page closes.
    func delete() async {
        await synchronizer.delete(id: id)
    }

    /// Whether "Renommer" can be confirmed with this name.
    nonisolated static func isValidName(_ name: String) -> Bool {
        ItineraryName.validated(name) != nil
    }

    var distanceText: String {
        summary.map { ActivityFormatters.distance($0.distance) } ?? "—"
    }

    /// "≈" when Open-Meteo provided altitudes (ADR-030 §3).
    var elevationText: String {
        guard let summary else { return "—" }
        let gain = ActivityFormatters.elevation(summary.elevationGain)
        return detail?.elevationSource.isApproximate == true ? "≈ \(gain)" : gain
    }

    var elevationSourceText: String? {
        detail.map { ItineraryMessages.elevationSource($0.elevationSource) }
    }

    private func show(_ cached: CachedItinerary) {
        summary = cached.summary
        if cached.detail?.track != detail?.track {
            profile = cached.detail?.track.elevationProfile()
        }
        detail = cached.detail
        if detail != nil {
            trackMessage = nil
        }
    }

    /// The observation shows the result; a `404` makes the Itinerary leave the cache.
    private func fetchDetail() async {
        do {
            try await synchronizer.loadDetail(id: id)
        } catch {
            guard detail == nil, error != .notFound else { return }
            trackMessage = error == .offline ? ItineraryMessages.trackUnavailableOffline : ItineraryMessages.trackUnavailable
        }
    }
}
