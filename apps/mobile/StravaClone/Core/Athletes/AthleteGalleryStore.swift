import Foundation
import Observation

/// The profile's Galerie tab (ADR-037 §9, §10), shared by my Profile tab and another athlete's
/// profile: every Media the viewer may see, loaded when the tab first opens, with infinite
/// scroll, and the full-screen viewer over all of them. `gallery_viewed` each time the tab opens.
@Observable
@MainActor
final class AthleteGalleryStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var items: [GalleryItem] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// Short-lived error shown over the grid (a page that could not be loaded).
    var notice: String?
    /// The full-screen viewer, opened by a tap on a tile.
    var mediaViewer: MediaViewerRequest?

    /// Two rows of three before the end.
    @ObservationIgnored let prefetchDistance = 6
    @ObservationIgnored private let loadGallery: LoadAthleteGallery
    @ObservationIgnored private let message: @MainActor (AthleteError) -> String
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private var athleteId: String?
    @ObservationIgnored private var isOwn = false
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var changeObservation: Task<Void, Never>?

    /// `message`: the feature's French text for a failed page.
    init(
        loadGallery: LoadAthleteGallery,
        message: @escaping @MainActor (AthleteError) -> String,
        activityChanges: ActivityChanges? = nil,
        analytics: any AnalyticsClient = NoAnalyticsClient()
    ) {
        self.loadGallery = loadGallery
        self.message = message
        self.analytics = analytics
        // Subscribed here, not in a view task: a pushed detail would cancel the tab's tasks.
        if let changes = activityChanges?.subscribe() {
            changeObservation = Task { [weak self] in
                for await change in changes {
                    await self?.apply(change)
                }
            }
        }
    }

    deinit {
        changeObservation?.cancel()
    }

    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// The Galerie tab opened (ADR-037 §13): says so, and loads the first page the first time.
    func open(athleteId: String, isOwn: Bool) async {
        analytics.capture(.galleryViewed(isOwn: isOwn))
        guard self.athleteId != athleteId || phase == .idle else { return }
        self.athleteId = athleteId
        self.isOwn = isOwn
        await refresh()
    }

    /// Pull-to-refresh, "Réessayer" and an expired URL: the first page again, once the tab was
    /// opened. A newer refresh wins over an older one.
    func refresh() async {
        guard let athleteId else { return }
        generation += 1
        let current = generation
        if items.isEmpty {
            phase = .loading
        }
        do {
            let page = try await loadGallery(athleteId: athleteId)
            guard current == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if items.isEmpty {
                phase = .failed(message: message(error))
            } else {
                notice = message(error)
            }
        }
    }

    /// Called when a tile appears: fetches the next page near the end of the grid.
    func loadMoreIfNeeded(current item: GalleryItem) async {
        guard
            let athleteId,
            let cursor = nextCursor,
            !isLoadingMore,
            let index = items.firstIndex(where: { $0.id == item.id }),
            index >= items.count - prefetchDistance
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do {
            let page = try await loadGallery(athleteId: athleteId, cursor: cursor)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            notice = message(error)
        }
    }

    /// A tap on a tile: the viewer over every loaded Media, with the "Voir l'activité" pill.
    func openMedia(_ media: ActivityMedia) {
        let viewerItems = items.map { item in
            MediaViewerItem(
                media: item.media,
                activity: MediaViewerActivity(id: item.activity.id, title: item.activity.title, startedAt: item.activity.startedAt)
            )
        }
        guard let request = MediaViewerRequest.gallery(viewerItems, at: media) else { return }
        analytics.capture(request.openedEvent(source: .gallery, isOwn: isOwn))
        mediaViewer = request
    }

    /// A change made in a detail (ADR-033 §7): a deleted Activity's Media leave the grid, a
    /// renamed one's follow; new or removed Media, or a deletion turned down, reload it.
    func apply(_ change: ActivityChange) async {
        guard phase != .idle else { return }
        switch change {
        case .deleted(let id):
            items.removeAll { $0.activity.id == id }
        case .restored:
            await refresh()
        case .updated(let post):
            let shown = items.filter { $0.activity.id == post.id }
            guard !shown.isEmpty else { return }
            if Set(shown.map(\.id)) != Set(post.media.map(\.id)) {
                await refresh()
                return
            }
            for index in items.indices where items[index].activity.id == post.id {
                items[index].activity = GalleryActivity(id: post.id, title: post.title, startedAt: post.startedAt)
            }
        case .engagement:
            break
        }
    }

    /// Sign-out: forgets the previous account's Gallery.
    func reset() {
        generation += 1
        items = []
        athleteId = nil
        isOwn = false
        nextCursor = nil
        phase = .idle
        notice = nil
        mediaViewer = nil
    }
}
