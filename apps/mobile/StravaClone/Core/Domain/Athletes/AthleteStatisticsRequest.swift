import Foundation

/// Opens an athlete's Statistiques screen (ADR-036 §4, §10), from my Plus tab or another
/// athlete's: each tab's `NavigationStack` registers it with the screen the app shell builds.
struct AthleteStatisticsRequest: Hashable, Sendable {
    let athleteId: String
    /// The athlete's practiced sports, for the sport picker; empty → the active sports.
    var sports: [SportType] = []
}
