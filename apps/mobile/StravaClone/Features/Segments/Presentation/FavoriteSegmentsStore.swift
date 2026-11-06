import Foundation
import Observation

/// Plus › « Segments » (ADR-039 §15): my favourite Segments, most recently added first, by
/// pages; reloaded each time the screen shows, so a new Segment appears.
@Observable
@MainActor
final class FavoriteSegmentsStore {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var items: [FavoriteSegment] = []
    private(set) var isLoadingMore = false

    @ObservationIgnored private let loadPage: LoadFavoriteSegments
    @ObservationIgnored private var nextCursor: String?

    init(loadPage: LoadFavoriteSegments) {
        self.loadPage = loadPage
    }

    var canLoadMore: Bool {
        nextCursor != nil && !isLoadingMore
    }

    /// The first page, again on a refresh.
    func load() async {
        if items.isEmpty { phase = .loading }
        do throws(SegmentError) {
            let page = try await loadPage(after: nil)
            items = page.items
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            if items.isEmpty { phase = .failed(Self.message(error)) }
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do throws(SegmentError) {
            let page = try await loadPage(after: cursor)
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            // The next scroll to the end tries again.
        }
    }

    private static func message(_ error: SegmentError) -> String {
        error == .offline ? SegmentMessages.connectionRequired : SegmentMessages.mySegmentsLoadFailed
    }
}

/// What a row of Plus › « Segments » shows.
struct FavoriteSegmentRow: Equatable {
    let segment: FavoriteSegment

    /// "2,00 km · 5,2 % · Cat. 4".
    var figures: String {
        let parts = [ActivityFormatters.distance(segment.distance), SegmentMessages.grade(segment.averageGrade)]
            + (segment.climbCategory.map { [$0.label] } ?? [])
        return parts.joined(separator: " · ")
    }

    var bestTime: String? {
        segment.myBestTime.map(ActivityFormatters.duration)
    }
}
