import Foundation
import Observation

/// The preview screen of a drawn Segment (ADR-039 §15): the full figures and profile, the name
/// (3 to 60 characters once trimmed, with a counter) and « Créer le Segment ». The refusals
/// show here: the duplicate with a link to the existing Segment, the quota.
@Observable
@MainActor
final class SegmentCreateStore {
    static let nameRange = 3...60

    let candidate: SegmentCandidate
    var name = ""
    private(set) var isCreating = false
    /// The existing Segment of the same sport, from the preview or the creation.
    private(set) var duplicate: SegmentRef?
    private(set) var isQuotaReached: Bool
    private(set) var failure: String?
    /// Set once created: « On cherche tes passages… ».
    private(set) var created: SegmentRef?

    @ObservationIgnored private let repository: any SegmentCreationRepository
    @ObservationIgnored private let isOnline: @MainActor () -> Bool

    init(
        candidate: SegmentCandidate,
        repository: any SegmentCreationRepository,
        isOnline: @escaping @MainActor () -> Bool
    ) {
        self.candidate = candidate
        self.repository = repository
        self.isOnline = isOnline
        duplicate = candidate.preview.duplicate
        isQuotaReached = candidate.preview.quotaLeft == 0
    }

    var sport: SegmentSport { candidate.sport }
    var preview: SegmentPreview { candidate.preview }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var counterText: String {
        "\(trimmedName.count)/\(Self.nameRange.upperBound)"
    }

    /// Nothing until something is typed.
    var nameHint: String? {
        let count = trimmedName.count
        if name.isEmpty || Self.nameRange.contains(count) { return nil }
        return count < Self.nameRange.lowerBound ? SegmentMessages.nameTooShort : SegmentMessages.nameTooLong
    }

    var canCreate: Bool {
        Self.nameRange.contains(trimmedName.count) && duplicate == nil && !isQuotaReached && !isCreating
    }

    /// The quota, or what went wrong last.
    var message: String? {
        isQuotaReached ? SegmentMessages.quotaReached : failure
    }

    func create() async {
        guard canCreate else { return }
        guard isOnline() else {
            failure = SegmentMessages.connectionRequired
            return
        }
        isCreating = true
        failure = nil
        defer { isCreating = false }
        do throws(SegmentCreationError) {
            created = try await repository.create(sport: sport, name: trimmedName, points: candidate.points)
        } catch {
            switch error {
            case .duplicate(let existing): duplicate = existing
            case .quotaReached: isQuotaReached = true
            case .offline: failure = SegmentMessages.connectionRequired
            case .rejected(let violations):
                failure = violations.first.map { SegmentMessages.violation($0, sport: sport) } ?? SegmentMessages.createFailed
            case .unavailable: failure = SegmentMessages.createFailed
            }
        }
    }
}
