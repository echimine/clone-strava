import Foundation

/// Where the altitudes of an Itinerary come from (ADR-030 §3). With `mixed` or
/// `openMeteo`, the elevation gain is shown as approximate.
enum ElevationSource: String, Hashable, Sendable {
    case ign
    case mixed
    case openMeteo = "open_meteo"
}
