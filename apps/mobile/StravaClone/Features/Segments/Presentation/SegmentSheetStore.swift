import Foundation
import Observation

/// A Segment's sheet (ADR-039 §15): loaded at opening and on pull-to-refresh (the retro-matching
/// banner follows it), the star, and the creator's « Renommer » and « Supprimer ». A failed
/// reload keeps what is shown and says so in a toast.
@MainActor
@Observable
final class SegmentSheetStore {
    enum Phase: Equatable {
        case loading
        case loaded(SegmentSheet)
        /// Deleted: « Ce Segment n'est plus disponible ».
        case gone
        case failed(String)
    }

    enum Deletion: Equatable {
        /// « Supprimer ce Segment ? »
        case confirming
        /// Someone else has an Effort on it: the explanation.
        case refused
    }

    private(set) var phase = Phase.loading
    var deletion: Deletion?
    var toast: String?

    @ObservationIgnored let segmentID: String
    @ObservationIgnored private let repository: any SegmentRepository
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let onDeleted: @MainActor () -> Void

    init(
        segmentID: String,
        repository: any SegmentRepository,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        onDeleted: @escaping @MainActor () -> Void = {}
    ) {
        self.segmentID = segmentID
        self.repository = repository
        self.analytics = analytics
        self.onDeleted = onDeleted
    }

    var sheet: SegmentSheet? {
        if case .loaded(let sheet) = phase { sheet } else { nil }
    }

    func load() async {
        do {
            phase = .loaded(try await repository.sheet(id: segmentID))
        } catch .notFound {
            phase = .gone
        } catch {
            if sheet == nil {
                phase = .failed(SegmentMessages.message(for: error))
            } else {
                toast = SegmentMessages.message(for: error)
            }
        }
    }

    /// The star counts me at once, and comes back as it was if the server says no.
    func toggleStar() async {
        guard var sheet else { return }
        let starred = !sheet.isStarred
        sheet.isStarred = starred
        sheet.favoriteCount = max(0, sheet.favoriteCount + (starred ? 1 : -1))
        phase = .loaded(sheet)
        do {
            try await repository.setStarred(id: segmentID, starred)
            if starred {
                analytics.capture(.segmentFavorited)
            }
        } catch {
            if var current = self.sheet {
                current.isStarred = !starred
                current.favoriteCount = max(0, current.favoriteCount + (starred ? -1 : 1))
                phase = .loaded(current)
            }
            toast = SegmentMessages.message(for: error)
        }
    }

    func rename(to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var sheet, SegmentMessages.isValidName(trimmed) else { return }
        do {
            try await repository.rename(id: segmentID, to: trimmed)
            sheet.name = trimmed
            phase = .loaded(sheet)
        } catch {
            toast = SegmentMessages.message(for: error)
        }
    }

    /// « Supprimer »: confirmed first, or explained when someone else has an Effort on it.
    func requestDelete() {
        guard let sheet, sheet.isMine else { return }
        deletion = sheet.canDelete ? .confirming : .refused
    }

    func confirmDelete() async {
        deletion = nil
        do {
            try await repository.delete(id: segmentID)
            onDeleted()
        } catch .hasOtherEfforts {
            deletion = .refused
        } catch .notFound {
            onDeleted()
        } catch {
            toast = SegmentMessages.message(for: error)
        }
    }
}
