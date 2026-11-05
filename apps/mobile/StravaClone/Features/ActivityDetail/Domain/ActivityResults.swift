import Foundation

/// « Résultats » of an Activity (`GET /v1/activities/:id/results`, ADR-039 §12): its Best
/// efforts and its Efforts on Segments, with their Medals.
struct ActivityResults: Hashable, Sendable {
    /// The Segments are still being looked for: « … » and « Recherche des Segments… ».
    var matchingInProgress: Bool
    /// A pool swim's pool length (« bassin de 25 m »), nil otherwise.
    var poolLength: Distance?
    /// Every Best effort not removed, shortest distance first.
    var bestEfforts: [BestEffortResult]
    /// In trace order; those in the privacy zone are left out for anyone but the author.
    var efforts: [SegmentEffortResult]

    static let empty = ActivityResults(matchingInProgress: false, poolLength: nil, bestEfforts: [], efforts: [])

    /// Medals of the Best efforts and of the Efforts: the count « Performances » shows.
    var medalCount: Int {
        bestEfforts.count { $0.medal != nil } + efforts.count { $0.medal != nil }
    }
}

/// The time of an Activity over one Record distance (ADR-039 §3).
struct BestEffortResult: Identifiable, Hashable, Sendable {
    /// Meters; the half marathon is 21 097,5.
    let distanceM: Double
    let elapsedTime: Duration
    let medal: Medal?
    /// The athlete's first time over this distance.
    let isFirst: Bool
    /// Still the athlete's Record over this distance.
    let isCurrentRecord: Bool
    /// « Retirer ce temps de mes meilleurs efforts »: the author only.
    let removable: Bool

    var id: Double { distanceM }
}

/// An Effort of the Activity on a Segment (ADR-039 §6, §8).
struct SegmentEffortResult: Identifiable, Hashable, Sendable {
    let id: String
    let segmentID: String
    let segmentName: String
    let segmentDistance: Distance
    let verified: Bool
    let elapsedTime: Duration
    let medal: Medal?
    /// The athlete's first Effort on this Segment: « · 1er passage ».
    let isFirstPass: Bool
    /// Its athlete is currently the Segment's Local Legend: the laurel crown.
    let localLegend: Bool
    /// The Segment's start, where its ribbon goes on the map.
    let startPoint: Coordinate
}

/// « Résultats » port (ADR-007): implemented over the API in Infrastructure, faked in tests.
protocol ActivityResultsRepository: Sendable {
    /// Same rights as the detail: `.notFound` when the Activity is not visible.
    func results(of id: ActivityID) async throws(ActivityDetailError) -> ActivityResults
    /// `DELETE /v1/activities/:id/best-efforts/:distanceM`: removed for good (ADR-039 §3).
    func removeBestEffort(of id: ActivityID, distanceM: Double) async throws(ActivityDetailError)
}
