import Foundation

/// « Performances » of an Activity (ADR-039 §12): its Medals the viewer may see, Best efforts and
/// Efforts on Segments added up by the API. Never stored.
struct MedalCounts: Hashable, Sendable {
    var gold: Int
    var silver: Int
    var bronze: Int

    static let none = MedalCounts(gold: 0, silver: 0, bronze: 0)

    /// The number « Performances » shows.
    var total: Int { gold + silver + bronze }
}
