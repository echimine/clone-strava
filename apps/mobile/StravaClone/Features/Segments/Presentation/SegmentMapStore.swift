import Foundation
import Observation

/// The Segments mode of the Map tab (ADR-039 §15, amends ADR-030). The zone is the one shown
/// once the camera first settles (on the athlete), then fixed: after a move, « Rechercher dans
/// cette zone » searches what is shown. Under zoom 10.5 nothing is searched nor drawn. The
/// filters search the same zone again. Cards are sorted by distance to the zone's centre;
/// scrolling to one or tapping its path highlights it.
@Observable
@MainActor
final class SegmentMapStore {
    /// Under this zoom: « Zoome pour voir les Segments » only (`SEGMENT_MAP_MIN_ZOOM`).
    static let minimumZoom = 10.5

    private(set) var filter = SegmentMapFilter()
    /// The zone last searched, fixed until « Rechercher dans cette zone ».
    private(set) var searchedArea: MapArea?
    /// What the map shows now.
    private(set) var camera: MapArea?
    /// The searched zone's Segments, nearest to its centre first.
    private(set) var segments: [MapSegment] = []
    private(set) var isLoading = false
    /// Why the last search failed, if it did.
    private(set) var failure: String?
    /// The server found the zone too large: zoom in.
    private var isZoneTooLarge = false
    /// A short-lived message (a star the server refused).
    var message: String?
    /// The card centred in the carousel, or the path last tapped.
    var focusedID: String?

    @ObservationIgnored private let searchSegments: SearchMapSegments
    @ObservationIgnored private let setFavorite: SetSegmentFavorite
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// Answers of an older search are dropped.
    @ObservationIgnored private var generation = 0

    init(searchSegments: SearchMapSegments, setFavorite: SetSegmentFavorite, analytics: any AnalyticsClient) {
        self.searchSegments = searchSegments
        self.setFavorite = setFavorite
        self.analytics = analytics
    }

    var isZoomedOut: Bool {
        guard let camera else { return false }
        return camera.zoom < Self.minimumZoom || (isZoneTooLarge && camera == searchedArea)
    }

    /// The Segments drawn and in the carousel: none while zoomed out.
    var visibleSegments: [MapSegment] {
        isZoomedOut ? [] : segments
    }

    /// « Rechercher dans cette zone »: after a move away from the searched zone, or a failure.
    var canSearchHere: Bool {
        guard let camera, !isZoomedOut, !isLoading else { return false }
        guard let searchedArea else { return true }
        return failure != nil || camera.isAway(from: searchedArea)
    }

    var focused: MapSegment? {
        visibleSegments.first { $0.id == focusedID }
    }

    var focusedPath: [Coordinate]? {
        focused?.path
    }

    var countLabel: String {
        SegmentMapMessages.count(segments.count)
    }

    var emptyMessage: String {
        filter.favoritesOnly ? SegmentMapMessages.noFavorite : SegmentMapMessages.noSegment
    }

    /// The camera came to rest: the first time it shows enough, its zone is searched.
    func cameraSettled(_ area: MapArea) async {
        camera = area
        if searchedArea == nil && area.zoom >= Self.minimumZoom {
            await search(area)
        }
    }

    func searchHere() async {
        guard let camera else { return }
        await search(camera)
    }

    /// A sport chip, or « Tous » (`nil`).
    func select(sport: SegmentSport?) async {
        guard filter.sport != sport else { return }
        filter.sport = sport
        await searchAgain()
    }

    func toggleFavoritesOnly() async {
        filter.favoritesOnly.toggle()
        await searchAgain()
    }

    /// The card's star, in one tap: shown at once, taken back if the server refuses.
    func toggleFavorite(_ id: String) async {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let isFavorite = !segments[index].isFavorite
        segments[index].isFavorite = isFavorite
        do {
            try await setFavorite(id, isFavorite)
            if isFavorite {
                analytics.capture(.segmentFavorited)
            }
        } catch {
            if let index = segments.firstIndex(where: { $0.id == id }) {
                segments[index].isFavorite = !isFavorite
            }
            message = SegmentMapMessages.favoriteFailed
        }
    }

    private func searchAgain() async {
        guard let searchedArea else { return }
        await search(searchedArea)
    }

    private func search(_ area: MapArea) async {
        generation += 1
        let current = generation
        searchedArea = area
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let found = try await searchSegments(in: area, filter: filter)
            guard current == generation else { return }
            let center = area.center
            segments = found.sorted { lhs, rhs in
                Self.distance(lhs, to: center) < Self.distance(rhs, to: center)
            }
            failure = nil
            isZoneTooLarge = false
            if !segments.contains(where: { $0.id == focusedID }) {
                focusedID = nil
            }
        } catch {
            guard current == generation else { return }
            segments = []
            focusedID = nil
            isZoneTooLarge = error == .zoneTooLarge
            failure = switch error {
            case .zoneTooLarge: nil
            case .offline: SegmentMapMessages.connectionRequired
            default: SegmentMapMessages.searchFailed
            }
        }
    }

    private static func distance(_ segment: MapSegment, to center: Coordinate) -> Double {
        segment.path.first?.distance(to: center).meters ?? .infinity
    }
}
