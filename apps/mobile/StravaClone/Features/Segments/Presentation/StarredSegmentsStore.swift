import Foundation
import Observation

/// Plus › « Segments » (ADR-039 §15): my starred Segments, most recently starred first, by
/// pages; reloaded each time the screen shows, so a new Segment appears.
@Observable
@MainActor
final class StarredSegmentsStore {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var items: [StarredSegment] = []
    private(set) var isLoadingMore = false

    @ObservationIgnored private let repository: any StarredSegmentsRepository
    @ObservationIgnored private var nextCursor: String?

    init(repository: any StarredSegmentsRepository) {
        self.repository = repository
    }

    var canLoadMore: Bool {
        nextCursor != nil && !isLoadingMore
    }

    /// The first page, again on a refresh.
    func load() async {
        if items.isEmpty { phase = .loading }
        do throws(StarredSegmentsError) {
            let page = try await repository.page(after: nil)
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
        do throws(StarredSegmentsError) {
            let page = try await repository.page(after: cursor)
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            // The next scroll to the end tries again.
        }
    }

    private static func message(_ error: StarredSegmentsError) -> String {
        switch error {
        case .offline: SegmentMessages.connectionRequired
        case .unavailable: SegmentMessages.mySegmentsLoadFailed
        }
    }
}

/// What a row of Plus › « Segments » shows.
struct StarredSegmentRow: Equatable {
    let segment: StarredSegment

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
