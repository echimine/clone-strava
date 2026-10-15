import Foundation

/// Where the athlete stands on the Itinerary followed during a Recording (ADR-031 §6, §7, §8),
/// as the Recording screen and the Live Activity show it. Compiled into the app and the widget
/// extension (ADR-031 §15).
enum ItineraryFollowState: String, Codable, Hashable, Sendable {
    /// No position within 50 m of the track yet, no Return path: distance left shows "—".
    case notSnapped
    case onTrack
    /// "Hors Itinéraire": off it for 3 points and 10 s, no Return path to show.
    case offTrack
    /// "Chemin recalculé".
    case returnPath
    /// "Itinéraire terminé".
    case finished

    /// The label of the distance left: the state replaces "Restant sur l'Itinéraire" off the
    /// track, on a Return path and at the end.
    var caption: String {
        switch self {
        case .notSnapped, .onTrack: "Restant sur l'Itinéraire"
        case .offTrack: "Hors Itinéraire"
        case .returnPath: "Chemin recalculé"
        case .finished: "Itinéraire terminé"
        }
    }
}
